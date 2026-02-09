// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {IRheoFactoryOffchainGetters} from "@rheo-fm/src/factory/interfaces/IRheoFactoryOffchainGetters.sol";
import {IRheoFactoryV1_7} from "@rheo-fm/src/factory/interfaces/IRheoFactoryV1_7.sol";
import {IRheoFactoryV1_8} from "@rheo-fm/src/factory/interfaces/IRheoFactoryV1_8.sol";

bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

/// @title IRheoFactory
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice The interface for the size factory
interface IRheoFactory is IRheoFactoryOffchainGetters, IRheoFactoryV1_7, IRheoFactoryV1_8 {
    /// @notice Set the size implementation
    /// @param _sizeImplementation The new size implementation
    function setRheoImplementation(address _sizeImplementation) external;

    /// @notice Set the non-transferrable token vault implementation
    /// @param _nonTransferrableTokenVaultImplementation The new non-transferrable token vault implementation
    function setNonTransferrableRebasingTokenVaultImplementation(address _nonTransferrableTokenVaultImplementation)
        external;

    /// @notice Creates a new market
    /// @dev The contract owner is set as the owner of the market
    function createMarket(
        InitializeFeeConfigParams calldata feeConfigParams,
        InitializeRiskConfigParams calldata riskConfigParams,
        InitializeOracleParams calldata oracleParams,
        InitializeDataParams calldata dataParams
    ) external returns (IRheo);

    /// @notice Creates a new borrow token vault
    /// @dev The contract owner is set as the owner of the borrow token vault
    ///      The borrow token vault needs to have adapters set after initialization
    function createBorrowTokenVault(IPool variablePool, IERC20Metadata underlyingBorrowToken)
        external
        returns (NonTransferrableRebasingTokenVault);

    /// @notice Creates a new price feed
    function createPriceFeed(PriceFeedParams calldata priceFeedParams) external returns (PriceFeed);

    /// @notice Check if an address is a registered market
    /// @param candidate The candidate to check
    /// @return True if the candidate is a registered market
    function isMarket(address candidate) external view returns (bool);

    /// @notice Removes a market from the registered markets
    /// @param market The market to remove
    function removeMarket(address market) external;
}
