// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {
    Initialize,
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {MarketShutdown, MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";
import {UpdateConfig, UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {
    SellCreditLimit,
    SellCreditLimitOnBehalfOfParams,
    SellCreditLimitParams
} from "@rheo-fm/src/market/libraries/actions/SellCreditLimit.sol";
import {
    SellCreditMarket,
    SellCreditMarketOnBehalfOfParams,
    SellCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {
    BuyCreditMarket,
    BuyCreditMarketOnBehalfOfParams,
    BuyCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {Claim, ClaimParams} from "@rheo-fm/src/market/libraries/actions/Claim.sol";
import {Deposit, DepositOnBehalfOfParams, DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {
    SetUserConfiguration,
    SetUserConfigurationOnBehalfOfParams,
    SetUserConfigurationParams
} from "@rheo-fm/src/market/libraries/actions/SetUserConfiguration.sol";
import {SetVault, SetVaultOnBehalfOfParams, SetVaultParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";
import {Withdraw, WithdrawOnBehalfOfParams, WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";

import {
    BuyCreditLimit,
    BuyCreditLimitOnBehalfOfParams,
    BuyCreditLimitParams
} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {Liquidate, LiquidateParams} from "@rheo-fm/src/market/libraries/actions/Liquidate.sol";

import {State} from "@rheo-fm/src/market/RheoStorage.sol";
import {Multicall} from "@rheo-fm/src/market/libraries/Multicall.sol";
import {
    Compensate,
    CompensateOnBehalfOfParams,
    CompensateParams
} from "@rheo-fm/src/market/libraries/actions/Compensate.sol";
import {PartialRepay, PartialRepayParams} from "@rheo-fm/src/market/libraries/actions/PartialRepay.sol";

import {Repay, RepayParams} from "@rheo-fm/src/market/libraries/actions/Repay.sol";
import {
    SelfLiquidate,
    SelfLiquidateOnBehalfOfParams,
    SelfLiquidateParams
} from "@rheo-fm/src/market/libraries/actions/SelfLiquidate.sol";
import {
    SetCopyLimitOrderConfigs,
    SetCopyLimitOrderConfigsOnBehalfOfParams,
    SetCopyLimitOrderConfigsParams
} from "@rheo-fm/src/market/libraries/actions/SetCopyLimitOrderConfigs.sol";

import {RiskLibrary} from "@rheo-fm/src/market/libraries/RiskLibrary.sol";

import {RheoView} from "@rheo-fm/src/market/RheoView.sol";
import {Events} from "@rheo-fm/src/market/libraries/Events.sol";

import {IMulticall} from "@rheo-fm/src/market/interfaces/IMulticall.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {IRheoV1_7} from "@rheo-fm/src/market/interfaces/v1.7/IRheoV1_7.sol";
import {IRheoV1_8} from "@rheo-fm/src/market/interfaces/v1.8/IRheoV1_8.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {PAUSER_ROLE} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {UserView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";

/// @title Rheo
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice See the documentation in {IRheo}.
contract Rheo is IRheo, RheoView, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Initialize for State;
    using UpdateConfig for State;
    using MarketShutdown for State;
    using Deposit for State;
    using Withdraw for State;
    using SellCreditMarket for State;
    using SellCreditLimit for State;
    using BuyCreditMarket for State;
    using BuyCreditLimit for State;
    using Repay for State;
    using Claim for State;
    using Liquidate for State;
    using SelfLiquidate for State;
    using Compensate for State;
    using PartialRepay for State;
    using SetUserConfiguration for State;
    using RiskLibrary for State;
    using Multicall for State;
    using SetCopyLimitOrderConfigs for State;
    using SetVault for State;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        InitializeFeeConfigParams calldata f,
        InitializeRiskConfigParams calldata r,
        InitializeOracleParams calldata o,
        InitializeDataParams calldata d
    ) external initializer {
        state.validateInitialize(owner, f, r, o, d);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        state.executeInitialize(f, r, o, d);
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(PAUSER_ROLE, owner);
    }

    function _hasRole(bytes32 role, address account) internal view returns (bool) {
        if (hasRole(role, account)) {
            return true;
        } else {
            return AccessControlUpgradeable(address(state.data.sizeFactory)).hasRole(role, account);
        }
    }

    modifier onlyRoleOrRheoFactoryHasRole(bytes32 role) {
        if (!_hasRole(role, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRoleOrRheoFactoryHasRole(DEFAULT_ADMIN_ROLE)
    {}

    /// @inheritdoc IRheoAdmin
    function marketShutdown(MarketShutdownParams calldata params)
        external
        override(IRheoAdmin)
        onlyRoleOrRheoFactoryHasRole(DEFAULT_ADMIN_ROLE)
    {
        // state.validateMarketShutdown(params); // no-op
        state.executeMarketShutdown(params);
    }

    /// @inheritdoc IRheoAdmin
    function updateConfig(UpdateConfigParams calldata params)
        external
        override(IRheoAdmin)
        onlyRoleOrRheoFactoryHasRole(DEFAULT_ADMIN_ROLE)
    {
        // state.validateUpdateConfig(params); // no-op
        state.executeUpdateConfig(params);
    }

    /// @inheritdoc IRheoAdmin
    function pause() public override(IRheoAdmin) onlyRoleOrRheoFactoryHasRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IRheoAdmin
    function unpause() public override(IRheoAdmin) onlyRoleOrRheoFactoryHasRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata _data) public payable override(IMulticall) returns (bytes[] memory results) {
        results = state.multicall(_data);
    }

    /// @inheritdoc IRheo
    function deposit(DepositParams calldata params) public payable override(IRheo) {
        depositOnBehalfOf(DepositOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_7
    function depositOnBehalfOf(DepositOnBehalfOfParams memory params)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateDeposit(params);
        state.executeDeposit(params);
    }

    /// @inheritdoc IRheo
    function withdraw(WithdrawParams calldata params) external payable override(IRheo) {
        withdrawOnBehalfOf(WithdrawOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_7
    function withdrawOnBehalfOf(WithdrawOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateWithdraw(externalParams);
        state.executeWithdraw(externalParams);
    }

    /// @inheritdoc IRheo
    function buyCreditLimit(BuyCreditLimitParams calldata params) external payable override(IRheo) {
        buyCreditLimitOnBehalfOf(BuyCreditLimitOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_7
    function buyCreditLimitOnBehalfOf(BuyCreditLimitOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateBuyCreditLimit(externalParams);
        state.executeBuyCreditLimit(externalParams);
    }

    /// @inheritdoc IRheo
    function sellCreditLimit(SellCreditLimitParams calldata params) external payable override(IRheo) {
        sellCreditLimitOnBehalfOf(SellCreditLimitOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_7
    function sellCreditLimitOnBehalfOf(SellCreditLimitOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateSellCreditLimit(externalParams);
        state.executeSellCreditLimit(externalParams);
    }

    /// @inheritdoc IRheo
    function buyCreditMarket(BuyCreditMarketParams calldata params) external payable override(IRheo) {
        buyCreditMarketOnBehalfOf(
            BuyCreditMarketOnBehalfOfParams({params: params, onBehalfOf: msg.sender, recipient: msg.sender})
        );
    }

    /// @inheritdoc IRheoV1_7
    function buyCreditMarketOnBehalfOf(BuyCreditMarketOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateBuyCreditMarket(externalParams);
        state.executeBuyCreditMarket(externalParams);
        if (externalParams.params.creditPositionId == RESERVED_ID) {
            state.validateUserIsNotBelowOpeningLimitBorrowCR(externalParams.params.borrower);
        }
    }

    /// @inheritdoc IRheo
    function sellCreditMarket(SellCreditMarketParams memory params) external payable override(IRheo) {
        sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({params: params, onBehalfOf: msg.sender, recipient: msg.sender})
        );
    }

    /// @inheritdoc IRheoV1_7
    function sellCreditMarketOnBehalfOf(SellCreditMarketOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateSellCreditMarket(externalParams);
        state.executeSellCreditMarket(externalParams);
        if (externalParams.params.creditPositionId == RESERVED_ID) {
            state.validateUserIsNotBelowOpeningLimitBorrowCR(externalParams.onBehalfOf);
        }
    }

    /// @inheritdoc IRheo
    function repay(RepayParams calldata params) external payable override(IRheo) nonReentrant whenNotPaused {
        state.validateRepay(params);
        state.executeRepay(params);
    }

    /// @inheritdoc IRheo
    function claim(ClaimParams calldata params) external payable override(IRheo) nonReentrant whenNotPaused {
        state.validateClaim(params);
        state.executeClaim(params);
    }

    /// @inheritdoc IRheo
    function liquidate(LiquidateParams calldata params)
        external
        payable
        override(IRheo)
        nonReentrant
        whenNotPaused
        returns (uint256 liquidatorProfitCollateralToken)
    {
        state.validateLiquidate(params);
        liquidatorProfitCollateralToken = state.executeLiquidate(params);
        state.validateMinimumCollateralProfit(params, liquidatorProfitCollateralToken);
    }

    /// @inheritdoc IRheo
    function selfLiquidate(SelfLiquidateParams calldata params) external payable override(IRheo) {
        selfLiquidateOnBehalfOf(
            SelfLiquidateOnBehalfOfParams({params: params, onBehalfOf: msg.sender, recipient: msg.sender})
        );
    }

    /// @inheritdoc IRheoV1_7
    function selfLiquidateOnBehalfOf(SelfLiquidateOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateSelfLiquidate(externalParams);
        state.executeSelfLiquidate(externalParams);
    }

    /// @inheritdoc IRheo
    function compensate(CompensateParams calldata params) external payable override(IRheo) {
        compensateOnBehalfOf(CompensateOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_7
    function compensateOnBehalfOf(CompensateOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        uint256 collateralRatioBefore = state.collateralRatio(externalParams.onBehalfOf);

        state.validateCompensate(externalParams);
        state.executeCompensate(externalParams);

        uint256 collateralRatioAfter = state.collateralRatio(externalParams.onBehalfOf);
        if (collateralRatioAfter <= collateralRatioBefore) {
            revert Errors.MUST_IMPROVE_COLLATERAL_RATIO(
                externalParams.onBehalfOf, collateralRatioBefore, collateralRatioAfter
            );
        }
    }

    /// @inheritdoc IRheo
    function partialRepay(PartialRepayParams calldata params)
        external
        payable
        override(IRheo)
        nonReentrant
        whenNotPaused
    {
        state.validatePartialRepay(params);
        state.executePartialRepay(params);
    }

    /// @inheritdoc IRheo
    function setUserConfiguration(SetUserConfigurationParams calldata params) external payable override(IRheo) {
        setUserConfigurationOnBehalfOf(SetUserConfigurationOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_7
    function setUserConfigurationOnBehalfOf(SetUserConfigurationOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateSetUserConfiguration(externalParams);
        state.executeSetUserConfiguration(externalParams);
    }

    /// @inheritdoc IRheo
    function setCopyLimitOrderConfigs(SetCopyLimitOrderConfigsParams calldata params)
        external
        payable
        override(IRheo)
    {
        setCopyLimitOrderConfigsOnBehalfOf(
            SetCopyLimitOrderConfigsOnBehalfOfParams({params: params, onBehalfOf: msg.sender})
        );
    }

    /// @inheritdoc IRheoV1_7
    function setCopyLimitOrderConfigsOnBehalfOf(SetCopyLimitOrderConfigsOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_7)
        nonReentrant
        whenNotPaused
    {
        state.validateSetCopyLimitOrderConfigs(externalParams);
        state.executeSetCopyLimitOrderConfigs(externalParams);
    }

    /// @inheritdoc IRheoV1_8
    function setVault(SetVaultParams calldata params) external payable override(IRheoV1_8) {
        setVaultOnBehalfOf(SetVaultOnBehalfOfParams({params: params, onBehalfOf: msg.sender}));
    }

    /// @inheritdoc IRheoV1_8
    function setVaultOnBehalfOf(SetVaultOnBehalfOfParams memory externalParams)
        public
        payable
        override(IRheoV1_8)
        nonReentrant
        whenNotPaused
    {
        state.validateSetVault(externalParams);
        state.executeSetVault(externalParams);
    }
}
