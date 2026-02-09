// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SetVaultParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";
import {SetVaultOnBehalfOfParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";

/// @title IRheoV1_8
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice The interface for the Rheo v1.8 view methods
interface IRheoV1_8 {
    // /// @notice Reinitialize the contract
    // function reinitialize() external;

    /// @notice Set the vault for a user
    /// @param params SetVaultParams struct containing the following fields:
    ///     - address vault: The address of the vault to set
    ///     - bool forfeitOldShares: Whether to forfeit old shares. WARNING: This will reset the user's balance to 0.
    function setVault(SetVaultParams calldata params) external payable;

    /// @notice Set the vault for a user on behalf of another user
    /// @param params SetVaultOnBehalfOfParams struct containing the following fields:
    ///     - address onBehalfOf: The address of the user to set the vault for
    ///     - address vault: The address of the vault to set
    ///     - bool forfeitOldShares: Whether to forfeit old shares. WARNING: This will reset the user's balance to 0.
    function setVaultOnBehalfOf(SetVaultOnBehalfOfParams calldata params) external payable;
}
