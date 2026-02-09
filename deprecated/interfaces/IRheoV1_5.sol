// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title IRheoV1_5
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice The interface for the size migration from v1.2 to v1.5
interface IRheoV1_5 {
    /// @notice Migrate the state from v1.2 to v1.5
    ///         On new markets, deployed through the RheoFactory, the reinitialization will not be necessary
    /// @dev The new NonTransferrableScaledTokenV1_5 contract must be able to hold underlying tokens
    ///      On all size markets, the two tokens will be non-zero addresses on the storage
    ///      During the migration,
    ///        The scaled balances of the users are transferred from the old (v1.2) to the new (v1.5) NonTransferrableScaledToken
    ///      To finalize the migration,
    ///        The underlying tokens must be transferred to the new NonTransferrableScaledTokenV1_5 contract
    ///      The migration is expected to be done in a single transaction
    function reinitialize(address borrowATokenV1_5, address[] calldata users) external;
}
