// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {IRheo, VERSION as MARKET_VERSION} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

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

    bytes4 private constant DATA_SELECTOR = bytes4(keccak256("data()"));
    bytes4 private constant RISK_CONFIG_SELECTOR = bytes4(keccak256("riskConfig()"));
    bytes4 private constant ORACLE_SELECTOR = bytes4(keccak256("oracle()"));
    bytes4 private constant VERSION_SELECTOR = bytes4(keccak256("version()"));

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
    event CreatePriceFeed(address indexed priceFeed);
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
            string.concat("Rheo ", underlyingBorrowToken.name(), " Vault"),
            string.concat("sv", underlyingBorrowToken.symbol()),
            underlyingBorrowToken.decimals()
        );
        borrowTokenVault = NonTransferrableRebasingTokenVault(
            address(new ERC1967Proxy(nonTransferrableRebasingTokenVaultImplementation, initializeData))
        );
        emit CreateBorrowTokenVault(address(borrowTokenVault));
    }

    function createPriceFeed(PriceFeedParams calldata priceFeedParams)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (PriceFeed priceFeed)
    {
        priceFeed = new PriceFeed(priceFeedParams);
        emit CreatePriceFeed(address(priceFeed));
    }

    function isMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate);
    }

    function isRheoMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate) && _isRheoMarket(candidate);
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

    function isAuthorizedAll(address operator, address onBehalfOf, uint256 actionsBitmap) external view returns (bool) {
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

    function getMarketDescriptions() external view returns (string[] memory descriptions) {
        descriptions = new string[](markets.length());
        for (uint256 i = 0; i < descriptions.length; i++) {
            descriptions[i] = _getMarketDescription(markets.at(i));
        }
    }

    function version() external pure returns (string memory) {
        return MARKET_VERSION;
    }

    function _getMarketDescription(address market) private view returns (string memory description) {
        string memory marketType = _isRheoMarket(market) ? "Rheo" : "Size";
        (address collateralToken, address borrowToken, bool hasData) = _tryGetMarketData(market);
        (uint256 crLiquidationPercent, bool hasRiskConfig) = _tryGetCrLiquidationPercent(market);
        if (!hasData || !hasRiskConfig) {
            return string.concat(marketType, " | ", Strings.toHexString(market));
        }

        string memory collateralSymbol = IERC20Metadata(collateralToken).symbol();
        string memory borrowSymbol = IERC20Metadata(borrowToken).symbol();
        string memory marketVersion = _getVersion(market);
        return string.concat(
            marketType,
            " | ",
            collateralSymbol,
            " | ",
            borrowSymbol,
            " | ",
            Strings.toString(crLiquidationPercent),
            " | ",
            marketVersion
        );
    }

    function _tryGetMarketData(address market)
        private
        view
        returns (address collateralToken, address borrowToken, bool)
    {
        (bool success, bytes memory marketData) = market.staticcall(abi.encodeWithSelector(DATA_SELECTOR));
        if (!success || marketData.length < 128) return (address(0), address(0), false);

        assembly ("memory-safe") {
            collateralToken := mload(add(marketData, 0x60))
            borrowToken := mload(add(marketData, 0x80))
        }
        return (collateralToken, borrowToken, true);
    }

    function _tryGetCrLiquidationPercent(address market) private view returns (uint256 crLiquidationPercent, bool) {
        (bool success, bytes memory riskConfigData) = market.staticcall(abi.encodeWithSelector(RISK_CONFIG_SELECTOR));
        if (!success || riskConfigData.length < 64) return (0, false);

        uint256 head0;
        uint256 crLiquidation;
        assembly ("memory-safe") {
            head0 := mload(add(riskConfigData, 0x20))
            crLiquidation := mload(add(riskConfigData, 0x40))
        }
        if (head0 == 0x20) {
            if (riskConfigData.length < 96) return (0, false);
            assembly ("memory-safe") {
                crLiquidation := mload(add(riskConfigData, 0x60))
            }
        }
        return (Math.mulDivDown(100, crLiquidation, PERCENT), true);
    }

    function _isRheoMarket(address market) internal view returns (bool) {
        (bool success, bytes memory result) = market.staticcall(abi.encodeWithSelector(ORACLE_SELECTOR));
        return success && result.length == 32;
    }

    function _getVersion(address market) private view returns (string memory marketVersion) {
        (bool success, bytes memory versionData) = market.staticcall(abi.encodeWithSelector(VERSION_SELECTOR));
        if (!success) return MARKET_VERSION;
        marketVersion = abi.decode(versionData, (string));
    }

    function _isValidActionsBitmap(uint256 actionsBitmap) private pure returns (bool) {
        uint256 maxValidBitmap = (uint256(1) << uint256(Action.NUMBER_OF_ACTIONS)) - 1;
        return actionsBitmap <= maxValidBitmap;
    }

    function _isActionSet(uint256 actionsBitmap, Action action) private pure returns (bool) {
        return (actionsBitmap & (uint256(1) << uint256(action))) != 0;
    }
}
