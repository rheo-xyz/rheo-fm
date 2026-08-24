// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CollateralAsset, MAX_COLLATERAL_ASSETS, State} from "@rheo-fm/src/market/RheoStorage.sol";

import {Initialize, InitializeCollateralAssetParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {CollateralBasketLibrary, PRICE_FEED_DECIMALS} from "@rheo-fm/src/market/libraries/CollateralBasketLibrary.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Events} from "@rheo-fm/src/market/libraries/Events.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

/// @title SetCollateralAsset
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Contains the admin logic for maintaining listed collateral assets
/// @dev Listing itself lives in `Initialize`, which is shared with market creation. There is no delisting by
///      design: pause deposits and set the cap to 0 instead.
library SetCollateralAsset {
    /// @notice Returns a listed collateral asset, reverting if the underlying is not listed
    /// @param state The state
    /// @param underlying The underlying collateral token
    function getListedCollateralAsset(State storage state, address underlying)
        internal
        view
        returns (CollateralAsset storage)
    {
        (bool found, uint256 index) = CollateralBasketLibrary.getCollateralAssetIndex(state, underlying);
        if (!found) {
            revert Errors.COLLATERAL_ASSET_NOT_LISTED(underlying);
        }
        return state.data.collateralAssets[index];
    }

    /// @notice Lists a new collateral asset in the market's basket
    /// @param state The state
    /// @param params The collateral asset parameters
    function executeAddCollateralAsset(State storage state, InitializeCollateralAssetParams memory params) external {
        if (state.data.collateralAssets.length >= MAX_COLLATERAL_ASSETS) {
            revert Errors.COLLATERAL_ASSETS_LIMIT_EXCEEDED(MAX_COLLATERAL_ASSETS);
        }
        Initialize.validateCollateralAssetParams(state, params, address(state.data.underlyingBorrowToken));
        Initialize.executeAddCollateralAsset(state, params);
    }

    /// @notice Updates the price feed of a listed collateral asset
    /// @param state The state
    /// @param underlying The underlying collateral token
    /// @param priceFeed The new price feed, in borrow token terms, with 18 decimals
    function executeSetCollateralAssetPriceFeed(State storage state, address underlying, address priceFeed) external {
        CollateralAsset storage asset = getListedCollateralAsset(state, underlying);

        if (priceFeed == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        if (IPriceFeed(priceFeed).decimals() != PRICE_FEED_DECIMALS) {
            revert Errors.INVALID_PRICE_FEED_DECIMALS(IPriceFeed(priceFeed).decimals());
        }
        if (IPriceFeed(priceFeed).getPrice() == 0) {
            revert Errors.NULL_AMOUNT();
        }

        asset.priceFeed = IPriceFeed(priceFeed);
        emit Events.CollateralAssetUpdated(underlying, priceFeed, asset.cap, asset.depositPaused);
    }

    /// @notice Updates the deposit cap of a listed collateral asset
    /// @dev Lowering the cap below the current supply blocks new deposits but does not force exits
    /// @param state The state
    /// @param underlying The underlying collateral token
    /// @param cap The new cap, in underlying base units
    function executeSetCollateralAssetCap(State storage state, address underlying, uint256 cap) external {
        CollateralAsset storage asset = getListedCollateralAsset(state, underlying);

        asset.cap = cap;
        emit Events.CollateralAssetUpdated(underlying, address(asset.priceFeed), cap, asset.depositPaused);
    }

    /// @notice Pauses or unpauses deposits of a listed collateral asset
    /// @param state The state
    /// @param underlying The underlying collateral token
    /// @param paused Whether new deposits of the asset should revert
    function executeSetCollateralAssetDepositPaused(State storage state, address underlying, bool paused) external {
        CollateralAsset storage asset = getListedCollateralAsset(state, underlying);

        asset.depositPaused = paused;
        emit Events.CollateralAssetUpdated(underlying, address(asset.priceFeed), asset.cap, paused);
    }
}
