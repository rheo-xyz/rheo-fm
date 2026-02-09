// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.sol";

import {Events} from "@src/market/libraries/Events.sol";
import {CREDIT_POSITION_ID_START, RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";

import {Math, PERCENT} from "@src/market/libraries/Math.sol";
import {BuyCreditMarket, BuyCreditMarketParams} from "@src/market/libraries/actions/BuyCreditMarket.sol";

contract SwapDataTest is BaseTest {
    function test_SwapData_borrowerAPR_lenderAPR() public {
        // I borrow for 6 months at 5% from you.
        // You are now lending at 5%.
        // You exit to someone demanding 4%.
        // New lender now earning 4%, while I’m still locked into the 5% deal.
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 100e6);
        uint256 tenor = _riskTenorAtIndex(4);
        uint256 maturity = _riskMaturityAtIndex(4);
        _buyCreditLimit(alice, maturity, _pointOfferAtIndex(4, 0.05e18));

        _deposit(bob, weth, 200e18);

        uint256 cash = 100e6;
        uint256 credit = Math.mulDivUp(cash, PERCENT + Math.aprToRatePerTenor(0.05e18, tenor), PERCENT);

        vm.expectEmit();
        emit Events.SwapData(CREDIT_POSITION_ID_START, bob, alice, credit, cash, cash, 0, 0, maturity);

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, cash, maturity, false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        assertEq(creditPositionId, CREDIT_POSITION_ID_START);
        assertEq(credit, size.getDebtPosition(debtPositionId).futureValue);
        assertEqApprox(size.getAPR(cash, credit, tenor), 0.05e18, 1e12);

        _deposit(candy, usdc, 200e6);
        _buyCreditLimit(candy, maturity, _pointOfferAtIndex(4, 0.04e18));

        uint256 newCash = Math.mulDivDown(credit, PERCENT, PERCENT + Math.aprToRatePerTenor(0.04e18, tenor));
        vm.expectEmit();
        emit Events.SwapData(creditPositionId, alice, candy, credit, newCash, newCash, 0, 0, maturity);

        _sellCreditMarket(alice, candy, creditPositionId, credit, maturity, true);

        assertEq(credit, size.getDebtPosition(debtPositionId).futureValue);
        assertEqApprox(size.getAPR(newCash, credit, tenor), 0.04e18, 0.001e18);
    }

    function test_SwapData_apr_with_fees() public {
        // The formula is correct but the cash for the lender and the borrower are different because of the swap fee leading to different APRs
        // Example
        // - Lender lends out 100 and gets a credit for 110 due 1Y so his APR is 10%
        // - Borrower does not receive 100 though but 100 - 0.5 = 99.5 since the fee is 0.5% APR on the issuance value which is the cash he would have received if no fee was charged = the amount disbursed by the lender so his APR is 10.5%
        // When the fragmentation fee is charged, the cash to consider is the amount after that fee has been charged
        _setPrice(1e18);

        _deposit(alice, usdc, 100e6);
        uint256 tenor = _riskTenorAtIndex(4);
        uint256 maturity = _riskMaturityAtIndex(4);
        _buyCreditLimit(alice, maturity, _pointOfferAtIndex(4, 0.1e18));

        _deposit(bob, weth, 200e18);

        uint256 cashIn = 100e6;
        uint256 credit = Math.mulDivUp(cashIn, PERCENT + Math.aprToRatePerTenor(0.1e18, tenor), PERCENT);
        uint256 swapFee = size.getSwapFee(cashIn, tenor);
        uint256 fragmentationFee = 0;
        uint256 cashOut = cashIn - swapFee;

        vm.expectEmit();
        emit Events.SwapData(
            CREDIT_POSITION_ID_START, bob, alice, credit, cashIn, cashOut, swapFee, fragmentationFee, maturity
        );
        _sellCreditMarket(bob, alice, RESERVED_ID, credit, maturity, true);

        uint256 lenderAPR = size.getAPR(cashIn, credit, tenor);
        uint256 borrowerAPR = size.getAPR(cashOut, credit, tenor);

        assertEqApprox(lenderAPR, 0.1e18, 1e14);
        assertGt(borrowerAPR, lenderAPR);
    }

    function test_SwapData_buyCreditMarket() public {
        _setPrice(1e18);

        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 200e18);
        _deposit(candy, usdc, 200e6);

        uint256 maturity = _riskMaturityAtIndex(2);
        _buyCreditLimit(alice, maturity, _pointOfferAtIndex(2, 0.2e18));
        _sellCreditLimit(alice, maturity, _pointOfferAtIndex(2, 0.1e18));
        _buyCreditLimit(candy, maturity, _pointOfferAtIndex(2, 0.1e18));

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, maturity);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: address(0),
            creditPositionId: creditPositionId,
            maturity: maturity,
            amount: 88e6,
            exactAmountIn: false,
            deadline: block.timestamp,
            minAPR: 0,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        BuyCreditMarket.SwapDataBuyCreditMarket memory swapData = size.getBuyCreditMarketSwapData(params);

        vm.expectEmit();
        emit Events.SwapData(
            creditPositionId,
            swapData.borrower,
            candy,
            swapData.creditAmountOut,
            swapData.cashAmountIn,
            swapData.cashAmountIn - swapData.swapFee - swapData.fragmentationFee,
            swapData.swapFee,
            swapData.fragmentationFee,
            swapData.maturity
        );
        _buyCreditMarket(candy, creditPositionId, params.amount, false);
    }
}
