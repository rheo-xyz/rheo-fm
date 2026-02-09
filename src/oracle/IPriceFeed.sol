// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title IPriceFeed
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
interface IPriceFeed {
    /// @notice Returns the price of the asset
    function getPrice() external view returns (uint256);
    /// @notice Returns the number of decimals of the price feed
    function decimals() external view returns (uint256);
}
