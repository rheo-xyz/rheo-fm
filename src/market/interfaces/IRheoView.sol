// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UserCopyLimitOrderConfigs} from "@rheo-fm/src/market/RheoStorage.sol";

import {CollateralAssetView, DataView, UserView} from "@rheo-fm/src/market/RheoViewData.sol";
import {CreditPosition, DebtPosition, LoanStatus} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {BuyCreditMarket, BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {SellCreditMarket, SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {IRheoViewV1_8} from "@rheo-fm/src/market/interfaces/v1.8/IRheoViewV1_8.sol";
/// @title IRheoView
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice View methods for the Rheo protocol

interface IRheoView is IRheoViewV1_8 {
    /// @notice Get the collateral ratio of a user
    /// @param user The address of the user
    /// @return The collateral ratio of the user
    function collateralRatio(address user) external view returns (uint256);

    /// @notice Get the total value of a user's collateral basket
    /// @dev Added in v2.0
    /// @param user The address of the user
    /// @return The value in borrow token base units
    function collateralValue(address user) external view returns (uint256);

    /// @notice Get the value of an amount of a listed collateral asset
    /// @dev Added in v2.0. Rounds down, matching the valuation of a realized liquidator profit.
    /// @param underlying The underlying collateral token
    /// @param amount The amount of the underlying collateral token
    /// @return The value in borrow token base units
    function getCollateralAssetValue(address underlying, uint256 amount) external view returns (uint256);

    /// @notice Get the market's collateral asset registry
    /// @dev Added in v2.0
    /// @return The collateral assets, in registry order
    function getCollateralAssets() external view returns (CollateralAssetView[] memory);

    /// @notice Get a user's balance of every listed collateral asset
    /// @dev Added in v2.0
    /// @param user The address of the user
    /// @return underlyings The underlying collateral tokens, in registry order
    /// @return balances The user's balances, aligned with `underlyings`
    function getUserCollateralBalances(address user)
        external
        view
        returns (address[] memory underlyings, uint256[] memory balances);

    /// @notice Get the fee configuration parameters
    /// @return The fee configuration parameters
    function feeConfig() external view returns (InitializeFeeConfigParams memory);

    /// @notice Get the risk configuration parameters
    /// @return The risk configuration parameters
    function riskConfig() external view returns (InitializeRiskConfigParams memory);

    /// @notice Get the oracle parameters
    /// @return The oracle parameters
    function oracle() external view returns (InitializeOracleParams memory);

    /// @notice Get the data view
    /// @return The data view
    function data() external view returns (DataView memory);

    /// @notice Get the user view for a given user
    /// @param user The address of the user
    /// @return The user view
    function getUserView(address user) external view returns (UserView memory);

    /// @notice Get the details of a debt position
    /// @param debtPositionId The ID of the debt position
    /// @return The DebtPosition struct containing the details of the debt position
    function getDebtPosition(uint256 debtPositionId) external view returns (DebtPosition memory);

    /// @notice Get the details of a credit position
    /// @param creditPositionId The ID of the credit position
    /// @return The CreditPosition struct containing the details of the credit position
    function getCreditPosition(uint256 creditPositionId) external view returns (CreditPosition memory);

    /// @notice Gets the swap data for buying credit as a market order
    /// @param params The input parameters for buying credit as a market order
    /// @return swapData The swap data for buying credit as a market order
    function getBuyCreditMarketSwapData(BuyCreditMarketParams memory params)
        external
        view
        returns (BuyCreditMarket.SwapDataBuyCreditMarket memory);

    /// @notice Returns the swap data for selling credit as a market order
    /// @param params The input parameters for selling credit as a market order
    /// @return swapData The swap data for selling credit as a market order
    function getSellCreditMarketSwapData(SellCreditMarketParams memory params)
        external
        view
        returns (SellCreditMarket.SwapDataSellCreditMarket memory);

    /// @notice Get the value of a storage slot
    /// @param key The key of the storage slot
    /// @return result The value of the storage slot
    function extSload(bytes32 key) external view returns (bytes32 result);

    /// @notice Get the version of the Rheo protocol
    /// @return The version of the Rheo protocol
    function version() external view returns (string memory);
}
