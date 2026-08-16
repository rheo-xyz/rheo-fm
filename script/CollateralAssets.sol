// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {InitializeCollateralAssetParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

/// @notice Builds a basket of exactly one uncapped collateral asset
/// @dev Shared by the deployment scripts and the fork tests, which all create single-collateral markets
function singleCollateralAsset(address underlying, address priceFeed)
    pure
    returns (InitializeCollateralAssetParams[] memory collateralAssets)
{
    collateralAssets = new InitializeCollateralAssetParams[](1);
    collateralAssets[0] =
        InitializeCollateralAssetParams({underlying: underlying, priceFeed: priceFeed, cap: type(uint256).max});
}
