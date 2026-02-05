// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISize} from "@src/market/interfaces/ISize.sol";
import {Errors} from "@src/market/libraries/Errors.sol";

import {RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@src/market/libraries/Math.sol";
import {BaseTest, Vars} from "@test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {Action, Authorization} from "@src/factory/libraries/Authorization.sol";
import {DEBT_POSITION_ID_START} from "@src/market/libraries/LoanLibrary.sol";
import {
    SellCreditMarketOnBehalfOfParams,
    SellCreditMarketParams
} from "@src/market/libraries/actions/SellCreditMarket.sol";

contract AuthorizationSellCreditMarketTest is BaseTest {
    function test_AuthorizationSellCreditMarket_sellCreditMarketOnBehalfOf() public {
        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 100e18);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));

        _setAuthorization(bob, candy, Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        Vars memory _before = _state();

        uint256 amount = 100e6;
        uint256 tenor = 150 days;
        uint256 maturity = _maturity(tenor);

        vm.prank(candy);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: amount,
                    maturity: maturity,
                    deadline: block.timestamp,
                    maxAPR: type(uint256).max,
                    exactAmountIn: false,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                }),
                onBehalfOf: bob,
                recipient: candy
            })
        );
        (uint256 debtPositionsCount,) = size.getPositionsCount();
        uint256 debtPositionId = DEBT_POSITION_ID_START + debtPositionsCount - 1;
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        uint256 ratePerTenor = Math.aprToRatePerTenor(0.03e18, tenor);
        uint256 issuanceValue = Math.mulDivDown(futureValue, PERCENT, PERCENT + ratePerTenor);
        uint256 swapFee = size.getSwapFee(issuanceValue, tenor);

        Vars memory _after = _state();

        assertEq(_after.alice.borrowTokenBalance, _before.alice.borrowTokenBalance - amount - swapFee);
        assertEq(_after.candy.borrowTokenBalance, _before.candy.borrowTokenBalance + amount);
        assertEq(_after.variablePool.collateralTokenBalance, _before.variablePool.collateralTokenBalance);
        assertEq(_after.bob.debtBalance, futureValue);
    }

    function test_AuthorizationSellCreditMarket_validation() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.SELL_CREDIT_MARKET)
        );
        vm.prank(alice);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: james,
                    creditPositionId: RESERVED_ID,
                    amount: 100e6,
                    maturity: block.timestamp + 150 days,
                    deadline: block.timestamp,
                    maxAPR: type(uint256).max,
                    exactAmountIn: false,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                }),
                onBehalfOf: bob,
                recipient: candy
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        vm.prank(alice);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 100e6,
                    maturity: block.timestamp + 150 days,
                    deadline: block.timestamp,
                    maxAPR: type(uint256).max,
                    exactAmountIn: false,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                }),
                onBehalfOf: alice,
                recipient: address(0)
            })
        );
    }
}
