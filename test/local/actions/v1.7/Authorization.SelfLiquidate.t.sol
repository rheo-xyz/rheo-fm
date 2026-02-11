// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {
    SelfLiquidateOnBehalfOfParams, SelfLiquidateParams
} from "@rheo-fm/src/market/libraries/actions/SelfLiquidate.sol";

import {BaseTest, Vars} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";
import {Action, Authorization} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

contract AuthorizationSelfLiquidateTest is BaseTest {
    function test_AuthorizationSelfLiquidate_selfLiquidateOnBehalfOf() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.SELF_LIQUIDATE));

        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 150e6);
        _deposit(bob, weth, 150e18);
        _deposit(liquidator, usdc, 10_000e6);

        assertEq(size.collateralRatio(bob), type(uint256).max);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        assertEq(size.getDebtPositionAssignedCollateral(debtPositionId), 150e18);
        assertEq(size.getDebtPosition(debtPositionId).futureValue, 100e6);
        assertEq(size.collateralRatio(bob), 1.5e18);
        assertTrue(!_isUserUnderwater(bob));
        assertTrue(!size.isDebtPositionLiquidatable(debtPositionId));

        _setPrice(0.5e18);
        assertEq(size.collateralRatio(bob), 0.75e18);

        uint256 debtInCollateralToken =
            size.debtTokenAmountToCollateralTokenAmount(size.getDebtPosition(debtPositionId).futureValue);

        vm.expectRevert();
        _liquidate(liquidator, debtPositionId, debtInCollateralToken, block.timestamp);

        Vars memory _before = _state();

        vm.prank(candy);
        size.selfLiquidateOnBehalfOf(
            SelfLiquidateOnBehalfOfParams({
                params: SelfLiquidateParams({creditPositionId: creditPositionId}),
                onBehalfOf: alice,
                recipient: candy
            })
        );

        Vars memory _after = _state();

        assertEq(_after.bob.collateralTokenBalance, _before.bob.collateralTokenBalance - 150e18, 0);
        assertEq(_after.candy.collateralTokenBalance, _before.candy.collateralTokenBalance + 150e18);
        assertEq(_after.bob.debtBalance, _before.bob.debtBalance - 100e6);
    }

    function test_AuthorizationSelfLiquidate_validation() public {
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 150e6);
        _deposit(bob, weth, 150e18);
        _deposit(liquidator, usdc, 10_000e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        vm.expectRevert(abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.SELF_LIQUIDATE));
        vm.prank(alice);
        size.selfLiquidateOnBehalfOf(
            SelfLiquidateOnBehalfOfParams({
                params: SelfLiquidateParams({creditPositionId: creditPositionId}),
                onBehalfOf: bob,
                recipient: candy
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        vm.prank(alice);
        size.selfLiquidateOnBehalfOf(
            SelfLiquidateOnBehalfOfParams({
                params: SelfLiquidateParams({creditPositionId: creditPositionId}),
                onBehalfOf: alice,
                recipient: address(0)
            })
        );
    }
}
