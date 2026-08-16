// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CollateralAsset, State} from "@rheo-fm/src/market/RheoStorage.sol";
import {CollateralAssetView} from "@rheo-fm/src/market/RheoViewData.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Math} from "@rheo-fm/src/market/libraries/Math.sol";

// number of decimals every collateral asset price feed must report
uint256 constant PRICE_FEED_DECIMALS = 18;

/// @title CollateralBasketLibrary
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Valuation and iteration helpers for the market's basket of collateral assets
/// @dev All `value` quantities are denominated in borrow token base units.
///      Rounding directionality: round down what counts towards a user's entitlement or collateral ratio,
///      round up what counts against the taker.
library CollateralBasketLibrary {
    /// @notice Returns the factors converting an amount of the collateral asset at `i` into borrow token value
    /// @dev Split out so that loops can cache the borrow token decimals across iterations
    /// @param state The state
    /// @param i The collateral asset index
    /// @param borrowDecimals The decimals of the underlying borrow token
    /// @return numerator The multiplication factor
    /// @return denominator The division factor
    function valuationFactors(State storage state, uint256 i, uint256 borrowDecimals)
        private
        view
        returns (uint256 numerator, uint256 denominator)
    {
        CollateralAsset storage asset = state.data.collateralAssets[i];
        numerator = asset.priceFeed.getPrice() * 10 ** borrowDecimals;
        denominator = 10 ** asset.underlying.decimals() * 10 ** PRICE_FEED_DECIMALS;
    }

    /// @notice Returns the value of `amount` of the collateral asset at index `i`, rounded down
    /// @param state The state
    /// @param i The collateral asset index
    /// @param amount The amount of the underlying collateral asset
    /// @return The value in borrow token base units
    function assetValueDown(State storage state, uint256 i, uint256 amount) public view returns (uint256) {
        (uint256 numerator, uint256 denominator) =
            valuationFactors(state, i, state.data.underlyingBorrowToken.decimals());
        return Math.mulDivDown(amount, numerator, denominator);
    }

    /// @notice Returns the value of `amount` of the collateral asset at index `i`, rounded up
    /// @param state The state
    /// @param i The collateral asset index
    /// @param amount The amount of the underlying collateral asset
    /// @return The value in borrow token base units
    function assetValueUp(State storage state, uint256 i, uint256 amount) public view returns (uint256) {
        (uint256 numerator, uint256 denominator) =
            valuationFactors(state, i, state.data.underlyingBorrowToken.decimals());
        return Math.mulDivUp(amount, numerator, denominator);
    }

    /// @notice Returns the total value of the account's collateral across the whole basket
    /// @dev Assets with a zero balance are skipped, so a user is only exposed to the price feeds of the assets
    ///      they actually hold
    /// @param state The state
    /// @param account The account
    /// @return value The value in borrow token base units
    function collateralValue(State storage state, address account) public view returns (uint256 value) {
        uint256 borrowDecimals = state.data.underlyingBorrowToken.decimals();
        uint256 length = state.data.collateralAssets.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 balance = state.data.collateralAssets[i].token.balanceOf(account);
            if (balance == 0) {
                continue;
            }
            (uint256 numerator, uint256 denominator) = valuationFactors(state, i, borrowDecimals);
            value += Math.mulDivDown(balance, numerator, denominator);
        }
    }

    /// @notice Returns the value of an amount of a listed collateral asset, rounded down
    /// @param state The state
    /// @param underlying The underlying collateral token
    /// @param amount The amount of the underlying collateral token
    /// @return The value in borrow token base units
    function getCollateralAssetValue(State storage state, address underlying, uint256 amount)
        public
        view
        returns (uint256)
    {
        (bool found, uint256 index) = getCollateralAssetIndex(state, underlying);
        if (!found) {
            revert Errors.COLLATERAL_ASSET_NOT_LISTED(underlying);
        }
        return assetValueDown(state, index, amount);
    }

    /// @notice Returns the market's collateral asset registry
    /// @dev No oracle calls: prices are read from each asset's feed directly
    /// @param state The state
    /// @return collateralAssets The collateral assets, in registry order
    function getCollateralAssets(State storage state)
        public
        view
        returns (CollateralAssetView[] memory collateralAssets)
    {
        uint256 length = state.data.collateralAssets.length;
        collateralAssets = new CollateralAssetView[](length);
        for (uint256 i = 0; i < length; i++) {
            CollateralAsset storage asset = state.data.collateralAssets[i];
            collateralAssets[i] = CollateralAssetView({
                underlying: asset.underlying,
                token: asset.token,
                priceFeed: asset.priceFeed,
                cap: asset.cap,
                depositPaused: asset.depositPaused
            });
        }
    }

    /// @notice Returns an account's balance of every listed collateral asset
    /// @param state The state
    /// @param account The account
    /// @return underlyings The underlying collateral tokens, in registry order
    /// @return balances The account's balances, aligned with `underlyings`
    function getUserCollateralBalances(State storage state, address account)
        public
        view
        returns (address[] memory underlyings, uint256[] memory balances)
    {
        uint256 length = state.data.collateralAssets.length;
        underlyings = new address[](length);
        balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            CollateralAsset storage asset = state.data.collateralAssets[i];
            underlyings[i] = address(asset.underlying);
            balances[i] = asset.token.balanceOf(account);
        }
    }

    /// @notice Returns the index of a listed collateral asset
    /// @param state The state
    /// @param underlying The underlying collateral token address
    /// @return found True if the asset is listed
    /// @return index The index into `collateralAssets`, meaningful only if `found` is true
    function getCollateralAssetIndex(State storage state, address underlying)
        internal
        view
        returns (bool found, uint256 index)
    {
        uint256 indexPlusOne = state.data.collateralAssetIndexPlusOne[underlying];
        if (indexPlusOne == 0) {
            return (false, 0);
        }
        return (true, indexPlusOne - 1);
    }

    /// @notice Transfers the same `numerator / denominator` fraction of every collateral asset balance
    /// @dev Each per-asset amount is rounded down, so up to 1 wei per asset is left behind with `from`
    /// @param state The state
    /// @param from The account to transfer the collateral from
    /// @param to The account to transfer the collateral to
    /// @param numerator The fraction numerator, must not exceed `denominator`
    /// @param denominator The fraction denominator
    /// @return tokens The underlying collateral token addresses, aligned with the registry
    /// @return amounts The transferred amounts, aligned with `tokens`
    /// @return value The value of the transferred collateral, rounded down
    function transferProRata(State storage state, address from, address to, uint256 numerator, uint256 denominator)
        public
        returns (address[] memory tokens, uint256[] memory amounts, uint256 value)
    {
        if (numerator > denominator) {
            revert Errors.INVALID_PRO_RATA_FRACTION(numerator, denominator);
        }

        uint256 length = state.data.collateralAssets.length;
        tokens = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            tokens[i] = address(state.data.collateralAssets[i].underlying);

            if (denominator == 0) {
                continue;
            }
            uint256 amount =
                Math.mulDivDown(state.data.collateralAssets[i].token.balanceOf(from), numerator, denominator);
            if (amount == 0) {
                continue;
            }

            amounts[i] = amount;
            state.data.collateralAssets[i].token.transferFrom(from, to, amount);
            value += assetValueDown(state, i, amount);
        }
    }
}
