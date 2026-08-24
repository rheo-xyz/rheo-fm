// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {CompensateParams} from "@rheo-fm/src/market/libraries/actions/Compensate.sol";
import {MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";
import {SellCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/SellCreditLimit.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {BaseTestBasket} from "@rheo-fm/test/local/actions/basket/BaseTestBasket.sol";

/// @title BasketActionsTest
/// @notice Covers the paths that previously only ran multi-asset code at basket-of-1 through the differential
///         tier: SelfLiquidate, the Compensate fragmentation fee, and MarketShutdown.
contract BasketActionsTest is BaseTestBasket {
    // --- SelfLiquidate ---

    function test_BasketActions_selfLiquidate_slices_every_held_asset() public {
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 1_000e6);
        _deposit(bob, assetA, 2e18); // 400 USDC
        _deposit(bob, assetC, 400e6); // 400 USDC

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 400e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        // severely underwater: CR below 100% makes the position self-liquidatable
        priceFeedA.setPrice(PRICE_A / 4);
        priceFeedC.setPrice(PRICE_C / 4);
        assertLt(size.collateralRatio(bob), PERCENT);

        uint256 credit = size.getCreditPosition(creditPositionId).credit;
        uint256 debt = size.getUserView(bob).debtBalance;

        (, uint256[] memory before) = size.getUserCollateralBalances(bob);
        uint256 expectedA = Math.mulDivDown(before[1], credit, debt);
        uint256 expectedC = Math.mulDivDown(before[3], credit, debt);

        _selfLiquidate(alice, creditPositionId);

        (, uint256[] memory lender) = size.getUserCollateralBalances(alice);
        assertEq(lender[1], expectedA, "asset A slice");
        assertEq(lender[3], expectedC, "asset C slice");
        assertEq(lender[2], 0, "an asset the borrower never held stays untouched");
    }

    // --- Compensate fragmentation fee ---

    /// @dev Mirrors the single-collateral fragmentation-fee test, but alice collateralises with two basket
    ///      assets so the fee has to be sliced across both
    function _setUpFragmentation() internal returns (uint256 creditPositionId) {
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, assetA, 5e18); // 1000 USDC
        _deposit(alice, assetC, 500e6); // 500 USDC
        _deposit(alice, usdc, 500e6);
        _deposit(bob, usdc, 500e6);
        _deposit(candy, assetB, 1e8); // an asset the price crash below does not touch
        _deposit(candy, usdc, 500e6);

        uint256[] memory aprs = new uint256[](1);
        uint256[] memory maturities = new uint256[](1);
        aprs[0] = 0.2e18;
        maturities[0] = _maturity(150 days);

        vm.prank(candy);
        size.sellCreditLimit(SellCreditLimitParams({maturities: maturities, aprs: aprs}));
        vm.prank(bob);
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));
        vm.prank(alice);
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));

        // alice borrows from bob, so she owns the debt the compensation repays
        vm.prank(alice);
        size.sellCreditMarket(
            SellCreditMarketParams({
                lender: bob,
                creditPositionId: type(uint256).max,
                maturity: maturities[0],
                amount: 100e6,
                exactAmountIn: true,
                deadline: block.timestamp,
                maxAPR: type(uint256).max,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        creditPositionId = type(uint256).max / 2;

        // and lends to candy, so she owns a credit position to compensate with
        vm.prank(alice);
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: candy,
                creditPositionId: type(uint256).max,
                amount: 100e6,
                maturity: maturities[0],
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_BasketActions_fragmentationFee_slices_across_the_basket() public {
        uint256 creditPositionId = _setUpFragmentation();

        uint256 totalValue = size.collateralValue(alice);
        uint256 feeValue = size.feeConfig().fragmentationFee;
        (, uint256[] memory before) = size.getUserCollateralBalances(alice);
        uint256 expectedA = Math.mulDivDown(before[1], feeValue, totalValue);
        uint256 expectedC = Math.mulDivDown(before[3], feeValue, totalValue);
        assertGt(expectedA, 0);
        assertGt(expectedC, 0);

        vm.prank(alice);
        size.compensate(
            CompensateParams({
                creditPositionWithDebtToRepayId: creditPositionId,
                creditPositionToCompensateId: creditPositionId + 1,
                amount: 10e6
            })
        );

        (, uint256[] memory fee) = size.getUserCollateralBalances(feeRecipient);
        assertEq(fee[1], expectedA, "fee slice of asset A");
        assertEq(fee[3], expectedC, "fee slice of asset C");
    }

    function test_BasketActions_fragmentationFee_reverts_when_the_basket_is_worth_less_than_the_fee() public {
        uint256 creditPositionId = _setUpFragmentation();

        // the whole basket collapses below the fee
        priceFeedA.setPrice(1);
        priceFeedC.setPrice(1);
        uint256 totalValue = size.collateralValue(alice);
        uint256 feeValue = size.feeConfig().fragmentationFee;
        assertLt(totalValue, feeValue);

        // read the fee before pranking: an external call inside the expectRevert argument would consume it
        vm.expectRevert(abi.encodeWithSelector(Errors.NOT_ENOUGH_COLLATERAL.selector, totalValue, feeValue));
        vm.prank(alice);
        size.compensate(
            CompensateParams({
                creditPositionWithDebtToRepayId: creditPositionId,
                creditPositionToCompensateId: creditPositionId + 1,
                amount: 10e6
            })
        );
    }

    // --- MarketShutdown ---

    function test_BasketActions_marketShutdown_drains_every_collateral_asset() public {
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 1_000e6);
        // marketShutdown force-liquidates as the caller, so the admin funds the repayments
        _deposit(address(this), usdc, 5_000e6);
        _deposit(bob, assetA, 3e18);
        _deposit(bob, assetB, 1e7);
        _deposit(bob, assetC, 200e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 300e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        vm.warp(_maturity(150 days) + 1);

        uint256[] memory debtPositionIds = new uint256[](1);
        debtPositionIds[0] = debtPositionId;
        uint256[] memory creditPositionIds = new uint256[](1);
        creditPositionIds[0] = creditPositionId;
        address[] memory users = new address[](3);
        users[0] = bob;
        users[1] = alice;
        users[2] = address(this);

        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: debtPositionIds,
                creditPositionIdsToClaim: creditPositionIds,
                usersToForceWithdraw: users,
                shouldCheckSupply: true
            })
        );

        // the force-withdraw loop must empty every listed asset, not just the first
        for (uint256 i = 0; i < _basketLength(); i++) {
            assertEq(size.getCollateralAssets()[i].token.totalSupply(), 0, "a collateral asset was left behind");
        }
    }
}
