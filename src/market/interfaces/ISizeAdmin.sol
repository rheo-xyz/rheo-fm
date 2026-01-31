// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MarketShutdownParams} from "@src/market/libraries/actions/MarketShutdown.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

/// @title ISizeAdmin
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for admin acitons
interface ISizeAdmin {
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

    /// @notice Pauses the protocol
    ///         Only callable by the PAUSER_ROLE
    function pause() external;

    /// @notice Unpauses the protocol
    ///         Only callable by the UNPAUSER_ROLE
    function unpause() external;
}
