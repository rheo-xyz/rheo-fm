// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {LiquidateParams} from "@rheo-fm/src/market/libraries/actions/Liquidate.sol";

import {BaseTestBasket} from "@rheo-fm/test/local/actions/basket/BaseTestBasket.sol";

contract LiquidateBasketTest is BaseTestBasket {
    uint256 internal debtPositionId;

    /// @dev Puts bob underwater holding two of the four listed assets, in different decimals
    function _setUpUnderwaterBorrower() internal {
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 1_000e6);
        _deposit(liquidator, usdc, 1_000e6);

        _deposit(bob, assetA, 2e18); // 400 USDC
        _deposit(bob, assetC, 400e6); // 400 USDC

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));
        debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 400e6, _maturity(150 days), false);

        // drop both feeds to 60%: collateral value 800 -> 480 USDC against a ~420 USDC debt.
        // that is underwater (CR ~1.14 < crLiquidation) but still profitable, so the liquidator entitlement
        // is a strict subset of the basket and explicit seizures can over-reach.
        priceFeedA.setPrice(PRICE_A * 6 / 10);
        priceFeedC.setPrice(PRICE_C * 6 / 10);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));
    }

    function test_LiquidateBasket_proRata_slices_every_held_asset() public {
        _setUpUnderwaterBorrower();

        uint256 totalValue = size.collateralValue(bob);
        uint256 entitlementValue = _entitlementValue();

        (, uint256[] memory before) = size.getUserCollateralBalances(bob);
        uint256 expectedA = Math.mulDivDown(before[1], entitlementValue, totalValue);
        uint256 expectedC = Math.mulDivDown(before[3], entitlementValue, totalValue);

        uint256 marketAssetABefore = assetA.balanceOf(address(size));

        _liquidate(liquidator, debtPositionId);

        // seizure moves deposit receipts only: the underlying never leaves the market, which is what keeps
        // liquidation working even if an issuer freezes transfers of the underlying
        assertEq(assetA.balanceOf(address(size)), marketAssetABefore);

        (, uint256[] memory liquidatorBalances) = size.getUserCollateralBalances(liquidator);
        assertEq(liquidatorBalances[1], expectedA);
        assertEq(liquidatorBalances[3], expectedC);

        // the borrower keeps at most one wei of dust per asset
        (, uint256[] memory remaining) = size.getUserCollateralBalances(bob);
        assertLe(remaining[1], before[1] - expectedA);
        assertLe(remaining[3], before[3] - expectedC);
    }

    function test_LiquidateBasket_explicit_seizes_a_single_asset() public {
        _setUpUnderwaterBorrower();

        // the "only take the name I can quote" case: seize the whole of asset A and leave asset C alone.
        // asset A is worth less than the entitlement, which explicit mode permits.
        (, uint256[] memory balances) = size.getUserCollateralBalances(bob);
        uint256 amountA = balances[1];
        assertLt(size.getCollateralAssetValue(address(assetA), amountA), _entitlementValue());

        _liquidate(liquidator, debtPositionId, 0, block.timestamp, _seizeOnly(1, amountA));

        (, uint256[] memory liquidatorBalances) = size.getUserCollateralBalances(liquidator);
        assertEq(liquidatorBalances[1], amountA);
        assertEq(liquidatorBalances[3], 0, "asset C untouched");
    }

    function test_LiquidateBasket_explicit_rejects_seizing_more_value_than_the_entitlement() public {
        _setUpUnderwaterBorrower();

        // the whole basket is worth more than the entitlement, so taking all of it must be rejected
        (, uint256[] memory balances) = size.getUserCollateralBalances(bob);
        uint256[] memory seize = new uint256[](_basketLength());
        seize[1] = balances[1];
        seize[3] = balances[3];
        assertGt(size.collateralValue(bob), _entitlementValue());

        vm.prank(liquidator);
        vm.expectRevert();
        size.liquidate(
            LiquidateParams({
                debtPositionId: debtPositionId,
                minimumCollateralProfitValue: 0,
                deadline: block.timestamp,
                seizeCollateralAmounts: seize
            })
        );
    }

    function test_LiquidateBasket_explicit_rejects_a_wrong_length_array() public {
        _setUpUnderwaterBorrower();

        uint256[] memory seize = new uint256[](2);

        vm.prank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SEIZE_COLLATERAL_AMOUNTS_LENGTH_MISMATCH.selector, _basketLength(), 2)
        );
        size.liquidate(
            LiquidateParams({
                debtPositionId: debtPositionId,
                minimumCollateralProfitValue: 0,
                deadline: block.timestamp,
                seizeCollateralAmounts: seize
            })
        );
    }

    function test_LiquidateBasket_explicit_rejects_more_than_the_borrower_holds() public {
        _setUpUnderwaterBorrower();

        (, uint256[] memory balances) = size.getUserCollateralBalances(bob);
        uint256[] memory seize = _seizeOnly(1, balances[1] + 1);

        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(Errors.NOT_ENOUGH_COLLATERAL.selector, balances[1], balances[1] + 1));
        size.liquidate(
            LiquidateParams({
                debtPositionId: debtPositionId,
                minimumCollateralProfitValue: 0,
                deadline: block.timestamp,
                seizeCollateralAmounts: seize
            })
        );
    }

    function test_LiquidateBasket_dust_picks_cannot_exceed_the_entitlement() public {
        _setUpUnderwaterBorrower();

        // one wei of every asset is valued rounding up, so a griefer cannot mint value out of rounding
        uint256[] memory seize = new uint256[](_basketLength());
        seize[1] = 1;
        seize[3] = 1;

        _liquidate(liquidator, debtPositionId, 0, block.timestamp, seize);

        (, uint256[] memory liquidatorBalances) = size.getUserCollateralBalances(liquidator);
        assertEq(liquidatorBalances[1], 1);
        assertEq(liquidatorBalances[3], 1);
    }

    /// @dev Recomputes the liquidator entitlement the way `executeLiquidate` does
    function _entitlementValue() internal view returns (uint256) {
        uint256 assignedValue = size.getDebtPositionAssignedCollateralValue(debtPositionId);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        if (assignedValue <= futureValue) {
            return assignedValue;
        }
        uint256 liquidatorReward = Math.min(
            assignedValue - futureValue, Math.mulDivUp(futureValue, size.feeConfig().liquidationRewardPercent, PERCENT)
        );
        return futureValue + liquidatorReward;
    }
}
