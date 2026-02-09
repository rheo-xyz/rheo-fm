// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";

import {BuyCreditLimitParams} from "@src/market/libraries/actions/BuyCreditLimit.sol";
import {BuyCreditMarketParams} from "@src/market/libraries/actions/BuyCreditMarket.sol";
import {PartialRepay} from "@src/market/libraries/actions/PartialRepay.sol";

import {PartialRepayParams} from "@src/market/libraries/actions/PartialRepay.sol";
import {SellCreditLimitParams} from "@src/market/libraries/actions/SellCreditLimit.sol";
import {BaseTest} from "@test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract PartialRepayTest is BaseTest {
    function test_PartialRepay_partialRepay_reduces_repaid_loan_debt_and_loan_credit() public {
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 400e18);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.5e18));

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 120e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        assertEq(size.getUserView(bob).borrowTokenBalance, 120e6);
        assertEq(size.getUserView(bob).debtBalance, futureValue);

        _deposit(bob, usdc, 100e6);

        _partialRepay(bob, creditPositionId, 70e6, bob);

        assertEq(size.getUserView(bob).borrowTokenBalance, 120e6 + 100e6 - 70e6, 150e6);
        assertEq(size.getUserView(bob).debtBalance, futureValue - 70e6);
    }

    function test_PartialRepay_partialRepay_is_permissionless() public {
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 400e18);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.5e18));

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 120e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        assertEq(size.getUserView(bob).borrowTokenBalance, 120e6);
        assertEq(size.getUserView(bob).debtBalance, futureValue);

        _deposit(james, usdc, 100e6);

        vm.prank(james);
        size.partialRepay(
            PartialRepayParams({creditPositionWithDebtToRepayId: creditPositionId, amount: 10e6, borrower: bob})
        );

        assertEq(size.getUserView(bob).debtBalance, futureValue - 10e6);
    }

    function testFuzz_PartialRepay_partialRepay_if_credit_lt_2x_minimumCreditBorrowToken(uint256 partialRepayAmount)
        public
    {
        // If the credit amount is less than 2 * minimumCreditBorrowToken, then it's only possible to partially repay the whole credit
        //   because both the repaying and remaining amount should be greater than minimumCreditBorrowToken
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("fragmentationFee", 0);
        _updateConfig("minimumCreditBorrowToken", 10e6);
        _deposit(alice, usdc, 60e6);
        _deposit(bob, weth, 120e18);
        _deposit(candy, usdc, 60e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        uint256 futureValue = size.riskConfig().minimumCreditBorrowToken * 3;

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, futureValue, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        uint256 credit2 = size.riskConfig().minimumCreditBorrowToken * 2 - 1;
        uint256 credit1 = futureValue - credit2;

        _sellCreditMarket(alice, candy, creditPositionId, credit2, _maturity(150 days), false);
        uint256 creditPositionId2 = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[1];

        assertEq(size.getDebtPosition(debtPositionId).futureValue, futureValue);
        assertEq(size.getCreditPosition(creditPositionId).credit, credit1);
        assertEq(size.getCreditPosition(creditPositionId2).credit, credit2);

        partialRepayAmount = bound(partialRepayAmount, 0, credit1);
        _deposit(bob, usdc, 100e6);

        vm.prank(bob);
        if (partialRepayAmount != credit1) {
            vm.expectRevert();
        }
        size.partialRepay(
            PartialRepayParams({
                creditPositionWithDebtToRepayId: creditPositionId,
                amount: partialRepayAmount,
                borrower: bob
            })
        );
    }

    function testFuzz_PartialRepay_partialRepay_after_minimumCreditBorrowToken_is_increased(uint256 amount) public {
        // If the credit amount is less than minimumCreditBorrowToken (it might happen when minimumCreditBorrowToken was increased later),
        //   it should be possible to partially repay even if the user wants to repay the full credit amount
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("fragmentationFee", 0);
        _updateConfig("minimumCreditBorrowToken", 10e6);
        _deposit(alice, usdc, 30e6);
        _deposit(bob, weth, 60e18);
        _deposit(candy, usdc, 30e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));

        amount = bound(amount, 20e6, 30e6);

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        _sellCreditMarket(alice, candy, creditPositionId, amount / 2, _maturity(150 days), false);
        uint256 creditPositionId2 = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[1];

        assertEq(size.getDebtPosition(debtPositionId).futureValue, amount);
        uint256 credit1 = amount - amount / 2;
        uint256 credit2 = amount / 2;
        assertEq(size.getCreditPosition(creditPositionId).credit, credit1);
        assertEq(size.getCreditPosition(creditPositionId2).credit, credit2);

        _updateConfig("minimumCreditBorrowToken", credit1 + 1);
        _deposit(bob, usdc, 100e6);

        vm.prank(bob);
        size.partialRepay(
            PartialRepayParams({creditPositionWithDebtToRepayId: creditPositionId, amount: credit1, borrower: bob})
        );
    }

    function test_PartialRepay_partialRepay_after_minimumCreditBorrowToken_is_increased_concrete() public {
        testFuzz_PartialRepay_partialRepay_after_minimumCreditBorrowToken_is_increased(
            15049080452407218967367839778534779
        );
    }
}
