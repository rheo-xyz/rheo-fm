// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

enum Action {
    DEPOSIT,
    WITHDRAW,
    BUY_CREDIT_LIMIT,
    SELL_CREDIT_LIMIT,
    BUY_CREDIT_MARKET,
    SELL_CREDIT_MARKET,
    SELF_LIQUIDATE,
    COMPENSATE,
    SET_USER_CONFIGURATION,
    SET_COPY_LIMIT_ORDER_CONFIGS,
    SET_VAULT,
    MANAGE_COLLECTION_SUBSCRIPTIONS,
    NUMBER_OF_ACTIONS
}

interface IRheoInitializer {
    function initialize(
        address owner,
        InitializeFeeConfigParams calldata f,
        InitializeRiskConfigParams calldata r,
        InitializeOracleParams calldata o,
        InitializeDataParams calldata d
    ) external;
}

contract SizeFactory is MulticallUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BORROW_RATE_UPDATER_ROLE = keccak256("BORROW_RATE_UPDATER_ROLE");

    address public sizeImplementation;
    address public rheoImplementation;
    address public nonTransferrableRebasingTokenVaultImplementation;
    ICollectionsManager public collectionsManager;

    mapping(address => uint256) public authorizationNonces;
    mapping(uint256 => mapping(address => mapping(address => uint256))) private authorizations;
    EnumerableSet.AddressSet private markets;

    event CreateMarket(address indexed market);
    event RemoveMarket(address indexed market);
    event CreateBorrowTokenVault(address indexed vault);
    event SetAuthorization(address indexed onBehalfOf, address indexed operator, uint256 actionsBitmap, uint256 nonce);
    event RevokeAllAuthorizations(address indexed account);
    event CollectionsManagerSet(address indexed oldCollectionsManager, address indexed newCollectionsManager);
    event SizeImplementationSet(address indexed oldImplementation, address indexed newImplementation);
    event RheoImplementationSet(address indexed oldImplementation, address indexed newImplementation);
    event NonTransferrableRebasingTokenVaultImplementationSet(
        address indexed oldImplementation, address indexed newImplementation
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Multicall_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(PAUSER_ROLE, owner);
        _grantRole(KEEPER_ROLE, owner);
        _grantRole(BORROW_RATE_UPDATER_ROLE, owner);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setSizeImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert Errors.NULL_ADDRESS();
        emit SizeImplementationSet(sizeImplementation, newImplementation);
        sizeImplementation = newImplementation;
        emit RheoImplementationSet(rheoImplementation, newImplementation);
        rheoImplementation = newImplementation;
    }

    function setRheoImplementation(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert Errors.NULL_ADDRESS();
        emit RheoImplementationSet(rheoImplementation, newImplementation);
        rheoImplementation = newImplementation;
    }

    function setNonTransferrableRebasingTokenVaultImplementation(address newImplementation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newImplementation == address(0)) revert Errors.NULL_ADDRESS();
        emit NonTransferrableRebasingTokenVaultImplementationSet(
            nonTransferrableRebasingTokenVaultImplementation, newImplementation
        );
        nonTransferrableRebasingTokenVaultImplementation = newImplementation;
    }

    function setCollectionsManager(address newCollectionsManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CollectionsManagerSet(address(collectionsManager), newCollectionsManager);
        collectionsManager = ICollectionsManager(newCollectionsManager);
    }

    function createMarketRheo(
        InitializeFeeConfigParams calldata feeConfigParamsRheo,
        InitializeRiskConfigParams calldata riskConfigParamsRheo,
        InitializeOracleParams calldata oracleParamsRheo,
        InitializeDataParams calldata dataParamsRheo
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        ERC1967Proxy proxy = new ERC1967Proxy(
            rheoImplementation,
            abi.encodeCall(
                IRheoInitializer.initialize,
                (msg.sender, feeConfigParamsRheo, riskConfigParamsRheo, oracleParamsRheo, dataParamsRheo)
            )
        );
        market = address(proxy);
        // slither-disable-next-line unused-return
        markets.add(market);
        emit CreateMarket(market);
    }

    function removeMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!markets.contains(market)) revert Errors.INVALID_MARKET(market);
        // slither-disable-next-line unused-return
        markets.remove(market);
        emit RemoveMarket(market);
    }

    function createBorrowTokenVault(IPool variablePool, IERC20Metadata underlyingBorrowToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (NonTransferrableRebasingTokenVault borrowTokenVault)
    {
        bytes memory initializeData = abi.encodeWithSelector(
            NonTransferrableRebasingTokenVault.initialize.selector,
            address(this),
            variablePool,
            underlyingBorrowToken,
            msg.sender,
            string.concat("Size ", underlyingBorrowToken.name(), " Vault"),
            string.concat("sv", underlyingBorrowToken.symbol()),
            underlyingBorrowToken.decimals()
        );
        borrowTokenVault = NonTransferrableRebasingTokenVault(
            address(new ERC1967Proxy(nonTransferrableRebasingTokenVaultImplementation, initializeData))
        );
        emit CreateBorrowTokenVault(address(borrowTokenVault));
    }

    function isMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate);
    }

    function isRheoMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate);
    }

    function setAuthorization(address operator, uint256 actionsBitmap) external {
        _setAuthorization(operator, msg.sender, actionsBitmap);
    }

    function _setAuthorization(address operator, address onBehalfOf, uint256 actionsBitmap) internal {
        if (operator == address(0)) revert Errors.NULL_ADDRESS();
        if (!_isValidActionsBitmap(actionsBitmap)) revert Errors.INVALID_ACTIONS_BITMAP(actionsBitmap);

        uint256 nonce = authorizationNonces[onBehalfOf];
        authorizations[nonce][operator][onBehalfOf] = actionsBitmap;
        emit SetAuthorization(onBehalfOf, operator, actionsBitmap, nonce);
    }

    function revokeAllAuthorizations() external {
        emit RevokeAllAuthorizations(msg.sender);
        authorizationNonces[msg.sender]++;
    }

    function isAuthorized(address operator, address onBehalfOf, Action action) public view returns (bool) {
        if (operator == onBehalfOf) return true;
        uint256 nonce = authorizationNonces[onBehalfOf];
        return _isActionSet(authorizations[nonce][operator][onBehalfOf], action);
    }

    function isAuthorizedAll(address operator, address onBehalfOf, uint256 actionsBitmap)
        external
        view
        returns (bool)
    {
        if (operator == onBehalfOf) return true;
        uint256 nonce = authorizationNonces[onBehalfOf];
        uint256 authorized = authorizations[nonce][operator][onBehalfOf];
        return (authorized & actionsBitmap) == actionsBitmap;
    }

    function callMarket(address market, bytes calldata data) external returns (bytes memory result) {
        if (!isMarket(market)) revert Errors.INVALID_MARKET(market);
        result = Address.functionCall(market, data);
    }

    function subscribeToCollections(uint256[] memory collectionIds) external {
        subscribeToCollectionsOnBehalfOf(collectionIds, msg.sender);
    }

    function unsubscribeFromCollections(uint256[] memory collectionIds) external {
        unsubscribeFromCollectionsOnBehalfOf(collectionIds, msg.sender);
    }

    function subscribeToCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        collectionsManager.subscribeUserToCollections(onBehalfOf, collectionIds);
    }

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
        setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
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

    function getLoanOfferAPR(address user, uint256 collectionId, address market, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256)
    {
        return collectionsManager.getLoanOfferAPR(user, collectionId, IRheo(market), rateProvider, maturity);
    }

    function getBorrowOfferAPR(
        address user,
        uint256 collectionId,
        address market,
        address rateProvider,
        uint256 maturity
    ) external view returns (uint256) {
        return collectionsManager.getBorrowOfferAPR(user, collectionId, IRheo(market), rateProvider, maturity);
    }

    function isBorrowAPRLowerThanLoanOfferAPRs(address user, uint256 borrowAPR, address market, uint256 maturity)
        external
        view
        returns (bool)
    {
        return collectionsManager.isBorrowAPRLowerThanLoanOfferAPRs(user, borrowAPR, IRheo(market), maturity);
    }

    function isLoanAPRGreaterThanBorrowOfferAPRs(address user, uint256 loanAPR, address market, uint256 maturity)
        external
        view
        returns (bool)
    {
        return collectionsManager.isLoanAPRGreaterThanBorrowOfferAPRs(user, loanAPR, IRheo(market), maturity);
    }

    function getMarket(uint256 index) external view returns (address) {
        return markets.at(index);
    }

    function getMarketsCount() external view returns (uint256) {
        return markets.length();
    }

    function getMarkets() external view returns (address[] memory result) {
        result = new address[](markets.length());
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = markets.at(i);
        }
    }

    function _isValidActionsBitmap(uint256 actionsBitmap) private pure returns (bool) {
        uint256 maxValidBitmap = (uint256(1) << uint256(Action.NUMBER_OF_ACTIONS)) - 1;
        return actionsBitmap <= maxValidBitmap;
    }

    function _isActionSet(uint256 actionsBitmap, Action action) private pure returns (bool) {
        return (actionsBitmap & (uint256(1) << uint256(action))) != 0;
    }
}
