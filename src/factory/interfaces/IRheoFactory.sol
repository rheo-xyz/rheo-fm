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
import {Action, ActionsBitmap} from "@rheo-fm/src/factory/libraries/Authorization.sol";

bytes32 constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 constant BORROW_RATE_UPDATER_ROLE = keccak256("BORROW_RATE_UPDATER_ROLE");
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

struct FactoryCopyLimitOrderConfig {
    uint256 minTenor;
    uint256 maxTenor;
    uint256 minAPR;
    uint256 maxAPR;
    int256 offsetAPR;
}

interface IRheoFactory {
    function setSizeImplementation(address newImplementation) external;

    function setRheoImplementation(address newImplementation) external;

    function setNonTransferrableRebasingTokenVaultImplementation(address newImplementation) external;

    function createMarketRheo(
        InitializeFeeConfigParams calldata feeConfigParamsRheo,
        InitializeRiskConfigParams calldata riskConfigParamsRheo,
        InitializeOracleParams calldata oracleParamsRheo,
        InitializeDataParams calldata dataParamsRheo
    ) external returns (address market);

    function createBorrowTokenVault(IPool variablePool, IERC20Metadata underlyingBorrowToken)
        external
        returns (address);

    function isMarket(address candidate) external view returns (bool);

    function isRheoMarket(address candidate) external view returns (bool);

    function setAuthorization(address operator, ActionsBitmap actionsBitmap) external;

    function revokeAllAuthorizations() external;

    function isAuthorized(address operator, address onBehalfOf, Action action) external view returns (bool);

    function isAuthorizedAll(address operator, address onBehalfOf, ActionsBitmap actionsBitmap)
        external
        view
        returns (bool);

    function callMarket(address market, bytes calldata data) external returns (bytes memory result);

    function subscribeToCollections(uint256[] memory collectionIds) external;

    function unsubscribeFromCollections(uint256[] memory collectionIds) external;

    function subscribeToCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) external;

    function unsubscribeFromCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) external;

    function setUserCollectionCopyLimitOrderConfigs(
        uint256 collectionId,
        FactoryCopyLimitOrderConfig memory copyLoanOfferConfig,
        FactoryCopyLimitOrderConfig memory copyBorrowOfferConfig
    ) external;

    function setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
        uint256 collectionId,
        FactoryCopyLimitOrderConfig memory copyLoanOfferConfig,
        FactoryCopyLimitOrderConfig memory copyBorrowOfferConfig,
        address onBehalfOf
    ) external;

    function getLoanOfferAPR(address user, uint256 collectionId, address market, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256);

    function getBorrowOfferAPR(
        address user,
        uint256 collectionId,
        address market,
        address rateProvider,
        uint256 maturity
    ) external view returns (uint256);

    function isBorrowAPRLowerThanLoanOfferAPRs(address user, uint256 borrowAPR, address market, uint256 maturity)
        external
        view
        returns (bool);

    function isLoanAPRGreaterThanBorrowOfferAPRs(address user, uint256 loanAPR, address market, uint256 maturity)
        external
        view
        returns (bool);

    function getMarket(uint256 index) external view returns (address);

    function getMarketsCount() external view returns (uint256);

    function getMarkets() external view returns (address[] memory);

    function getMarketDescriptions() external view returns (string[] memory descriptions);

    function version() external view returns (string memory);
}
