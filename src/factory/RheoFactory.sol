// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {
    BuyCreditLimitOnBehalfOfParams,
    BuyCreditLimitParams
} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {
    SellCreditLimitOnBehalfOfParams,
    SellCreditLimitParams
} from "@rheo-fm/src/market/libraries/actions/SellCreditLimit.sol";

import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";
import {MarketFactoryLibrary} from "@rheo-fm/src/factory/libraries/MarketFactoryLibrary.sol";

import {NonTransferrableRebasingTokenVaultLibrary} from
    "@rheo-fm/src/factory/libraries/NonTransferrableRebasingTokenVaultLibrary.sol";
import {PriceFeedFactoryLibrary} from "@rheo-fm/src/factory/libraries/PriceFeedFactoryLibrary.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {IPriceFeedV1_5_2} from "@rheo-fm/src/oracle/v1.5.2/IPriceFeedV1_5_2.sol";

import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {RheoFactoryEvents} from "@rheo-fm/src/factory/RheoFactoryEvents.sol";
import {RheoFactoryOffchainGetters} from "@rheo-fm/src/factory/RheoFactoryOffchainGetters.sol";
import {Action, ActionsBitmap, Authorization} from "@rheo-fm/src/factory/libraries/Authorization.sol";

import {IRheoFactoryV1_7} from "@rheo-fm/src/factory/interfaces/IRheoFactoryV1_7.sol";
import {IRheoFactoryV1_8} from "@rheo-fm/src/factory/interfaces/IRheoFactoryV1_8.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";

import {PAUSER_ROLE} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";

/// @title RheoFactory
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice See the documentation in {IRheoFactory}.
/// @dev Expects `AccessControlUpgradeable` to have a single DEFAULT_ADMIN_ROLE role address set.
contract RheoFactory is
    IRheoFactory,
    RheoFactoryOffchainGetters,
    RheoFactoryEvents,
    MulticallUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Multicall_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc IRheoFactory
    function setRheoImplementation(address _sizeImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_sizeImplementation == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        emit RheoImplementationSet(sizeImplementation, _sizeImplementation);
        sizeImplementation = _sizeImplementation;
    }

    /// @inheritdoc IRheoFactory
    function setNonTransferrableRebasingTokenVaultImplementation(address _nonTransferrableTokenVaultImplementation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_nonTransferrableTokenVaultImplementation == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        emit NonTransferrableRebasingTokenVaultImplementationSet(
            nonTransferrableTokenVaultImplementation, _nonTransferrableTokenVaultImplementation
        );
        nonTransferrableTokenVaultImplementation = _nonTransferrableTokenVaultImplementation;
    }

    function setCollectionsManager(ICollectionsManager _collectionsManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CollectionsManagerSet(address(collectionsManager), address(_collectionsManager));
        collectionsManager = _collectionsManager;
    }

    /// @inheritdoc IRheoFactory
    function createMarket(
        InitializeFeeConfigParams calldata feeConfigParams,
        InitializeRiskConfigParams calldata riskConfigParams,
        InitializeOracleParams calldata oracleParams,
        InitializeDataParams calldata dataParams
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (IRheo market) {
        address admin = msg.sender;
        market = MarketFactoryLibrary.createMarket(
            sizeImplementation, admin, feeConfigParams, riskConfigParams, oracleParams, dataParams
        );
        // slither-disable-next-line unused-return
        markets.add(address(market));
        emit CreateMarket(address(market));
    }

    /// @inheritdoc IRheoFactory
    function removeMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!markets.contains(market)) {
            revert Errors.INVALID_MARKET(market);
        }
        // slither-disable-next-line unused-return
        markets.remove(market);
        emit RemoveMarket(market);
    }

    /// @inheritdoc IRheoFactory
    function createBorrowTokenVault(IPool variablePool, IERC20Metadata underlyingBorrowToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (NonTransferrableRebasingTokenVault borrowTokenVault)
    {
        address admin = msg.sender;
        borrowTokenVault = NonTransferrableRebasingTokenVaultLibrary.createNonTransferrableRebasingTokenVault(
            nonTransferrableTokenVaultImplementation, admin, variablePool, underlyingBorrowToken
        );
        emit CreateBorrowTokenVault(address(borrowTokenVault));
    }

    /// @inheritdoc IRheoFactory
    function createPriceFeed(PriceFeedParams memory _priceFeedParams)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (PriceFeed priceFeed)
    {
        priceFeed = PriceFeedFactoryLibrary.createPriceFeed(_priceFeedParams);
        emit CreatePriceFeed(address(priceFeed));
    }

    /// @inheritdoc IRheoFactory
    function isMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate);
    }

    /// @inheritdoc IRheoFactoryV1_7
    function setAuthorization(address operator, ActionsBitmap actionsBitmap) external override(IRheoFactoryV1_7) {
        // validate msg.sender
        // N/A

        _setAuthorization(operator, msg.sender, actionsBitmap);
    }

    function _setAuthorization(address operator, address onBehalfOf, ActionsBitmap actionsBitmap) internal {
        // validate operator
        if (operator == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        // validate actionsBitmap
        if (!Authorization.isValid(actionsBitmap)) {
            revert Errors.INVALID_ACTIONS_BITMAP(Authorization.toUint256(actionsBitmap));
        }

        uint256 nonce = authorizationNonces[onBehalfOf];
        emit SetAuthorization(onBehalfOf, operator, Authorization.toUint256(actionsBitmap), nonce);
        authorizations[nonce][operator][onBehalfOf] = actionsBitmap;
    }

    /// @inheritdoc IRheoFactoryV1_7
    function revokeAllAuthorizations() external override(IRheoFactoryV1_7) {
        emit RevokeAllAuthorizations(msg.sender);
        authorizationNonces[msg.sender]++;
    }

    /// @inheritdoc IRheoFactoryV1_7
    function isAuthorized(address operator, address onBehalfOf, Action action) public view returns (bool) {
        if (operator == onBehalfOf) {
            return true;
        } else {
            uint256 nonce = authorizationNonces[onBehalfOf];
            return Authorization.isActionSet(authorizations[nonce][operator][onBehalfOf], action);
        }
    }

    /// @inheritdoc IRheoFactoryV1_8
    function callMarket(IRheo market, bytes calldata data) external returns (bytes memory result) {
        if (!isMarket(address(market))) {
            revert Errors.INVALID_MARKET(address(market));
        }
        result = Address.functionCall(address(market), data);
    }

    /// @inheritdoc IRheoFactoryV1_8
    function subscribeToCollections(uint256[] memory collectionIds) external {
        return subscribeToCollectionsOnBehalfOf(collectionIds, msg.sender);
    }

    /// @inheritdoc IRheoFactoryV1_8
    function unsubscribeFromCollections(uint256[] memory collectionIds) external {
        return unsubscribeFromCollectionsOnBehalfOf(collectionIds, msg.sender);
    }

    /// @inheritdoc IRheoFactoryV1_8
    function subscribeToCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        collectionsManager.subscribeUserToCollections(onBehalfOf, collectionIds);
    }

    /// @inheritdoc IRheoFactoryV1_8
    function unsubscribeFromCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        collectionsManager.unsubscribeUserFromCollections(onBehalfOf, collectionIds);
    }

    function setUserCollectionCopyLimitOrderConfigs(
        uint256 collectionId,
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig
    ) external {
        return setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
            collectionId, copyLoanOfferConfig, copyBorrowOfferConfig, msg.sender
        );
    }

    function setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
        uint256 collectionId,
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig,
        address onBehalfOf
    ) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        collectionsManager.setUserCollectionCopyLimitOrderConfigs(
            onBehalfOf, collectionId, copyLoanOfferConfig, copyBorrowOfferConfig
        );
    }

    /// @inheritdoc IRheoFactoryV1_8
    function getLoanOfferAPR(address user, uint256 collectionId, IRheo market, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256)
    {
        return collectionsManager.getLoanOfferAPR(user, collectionId, market, rateProvider, maturity);
    }

    /// @inheritdoc IRheoFactoryV1_8
    function getBorrowOfferAPR(address user, uint256 collectionId, IRheo market, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256)
    {
        return collectionsManager.getBorrowOfferAPR(user, collectionId, market, rateProvider, maturity);
    }

    function isBorrowAPRLowerThanLoanOfferAPRs(address user, uint256 borrowAPR, IRheo market, uint256 maturity)
        external
        view
        returns (bool)
    {
        return collectionsManager.isBorrowAPRLowerThanLoanOfferAPRs(user, borrowAPR, market, maturity);
    }

    function isLoanAPRGreaterThanBorrowOfferAPRs(address user, uint256 loanAPR, IRheo market, uint256 maturity)
        external
        view
        returns (bool)
    {
        return collectionsManager.isLoanAPRGreaterThanBorrowOfferAPRs(user, loanAPR, market, maturity);
    }
}
