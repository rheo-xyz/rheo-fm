// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {InitializeCollateralAssetParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

/// @title IRheoAdmin
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice The interface for admin acitons
/// @dev v2.0 additions are declared here rather than in a versioned `interfaces/v2.0/` interface, unlike
///      rheo-solidity's ISizeFactoryV2. The versioned pattern exists so an existing consumer keeps compiling
///      across an additive upgrade; v2.0 is a clean ABI break deployed to fresh markets, so no such consumer
///      exists. rheo-solidity differs because one SizeFactory must keep serving both v1.9 Size markets and
///      v2.0 Rheo markets, which makes the split load-bearing there.
interface IRheoAdmin {
    /// @notice Updates the configuration of the protocol
    ///         Only callable by the DEFAULT_ADMIN_ROLE
    /// @dev For `address` parameters, the `value` is converted to `uint160` and then to `address`
    /// @param params UpdateConfigParams struct containing the following fields:
    ///     - string key: The configuration parameter to update
    ///     - uint256 value: The value to update
    function updateConfig(UpdateConfigParams calldata params) external;

    /// @notice Shuts down the market
    ///         Only callable by the DEFAULT_ADMIN_ROLE
    /// @dev Added in v1.8.4
    /// @dev Griefers can DoS a full shutdown by creating many self-borrows; the admin can skip force liquidating those
    ///      positions (leaving some collateral locked) to keep the shutdown feasible.
    /// @dev Set `shouldCheckSupply` to false to perform shutdown steps across multiple transactions (e.g., when
    ///      there are too many open loans to fit in a single block).
    /// @dev Pausing the market is a separate admin action and can be done in the same multicall as shutdown.
    /// @dev Only collateral tokens are forced withdrawn; borrow tokens can still be withdrawn in other non-shutdown markets.
    /// @dev The caller must have enough borrow tokens to liquidate all open debt positions.
    /// @param params MarketShutdownParams struct containing the following fields:
    ///     - uint256[] debtPositionIdsToForceLiquidate: The ids of the debt positions to force liquidate
    ///     - uint256[] creditPositionIdsToClaim: The ids of the credit positions to claim
    ///     - address[] usersToForceWithdraw: The addresses to force withdraw collateral for
    ///     - bool shouldCheckSupply: Whether to enforce zero supply checks
    function marketShutdown(MarketShutdownParams calldata params) external;

    /// @notice Lists a new collateral asset in the market's basket
    ///         Only callable by the DEFAULT_ADMIN_ROLE
    /// @dev Added in v2.0. Listing is permanent: there is no removal function, because balances may exist and the
    ///      price feed must keep answering until the deposit receipt supply is zero. Delist by pausing deposits and
    ///      setting the cap to 0.
    /// @param params InitializeCollateralAssetParams struct containing the following fields:
    ///     - address underlying: The underlying collateral token
    ///     - address priceFeed: The price feed, in borrow token terms, with 18 decimals
    ///     - uint256 cap: The maximum total deposited amount, in underlying base units
    function addCollateralAsset(InitializeCollateralAssetParams calldata params) external;

    /// @notice Updates the price feed of a listed collateral asset
    ///         Only callable by the DEFAULT_ADMIN_ROLE
    /// @dev Added in v2.0
    /// @param underlying The underlying collateral token
    /// @param priceFeed The new price feed, in borrow token terms, with 18 decimals
    function setCollateralAssetPriceFeed(address underlying, address priceFeed) external;

    /// @notice Updates the deposit cap of a listed collateral asset
    ///         Only callable by the DEFAULT_ADMIN_ROLE
    /// @dev Added in v2.0. Lowering the cap below the current supply blocks new deposits but does not force exits.
    /// @param underlying The underlying collateral token
    /// @param cap The new cap, in underlying base units
    function setCollateralAssetCap(address underlying, uint256 cap) external;

    /// @notice Pauses or unpauses deposits of a listed collateral asset
    ///         Only callable by the DEFAULT_ADMIN_ROLE
    /// @dev Added in v2.0. Withdrawals of a deposit-paused asset remain enabled.
    /// @param underlying The underlying collateral token
    /// @param paused Whether new deposits of the asset should revert
    function setCollateralAssetDepositPaused(address underlying, bool paused) external;

    /// @notice Pauses the protocol
    ///         Only callable by the PAUSER_ROLE
    function pause() external;

    /// @notice Unpauses the protocol
    ///         Only callable by the UNPAUSER_ROLE
    function unpause() external;
}
