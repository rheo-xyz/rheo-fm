// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RheoStorage, State, User} from "@rheo-fm/src/market/RheoStorage.sol";

import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {
    CREDIT_POSITION_ID_START,
    CreditPosition,
    DEBT_POSITION_ID_START,
    DebtPosition,
    LoanLibrary,
    LoanStatus,
    RESERVED_ID
} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {UpdateConfig} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {DataView, UserView} from "@rheo-fm/src/market/RheoViewData.sol";
import {AccountingLibrary} from "@rheo-fm/src/market/libraries/AccountingLibrary.sol";
import {RiskLibrary} from "@rheo-fm/src/market/libraries/RiskLibrary.sol";

import {ReentrancyGuardUpgradeableWithViewModifier} from
    "@rheo-fm/src/helpers/ReentrancyGuardUpgradeableWithViewModifier.sol";
import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";
import {IRheoViewV1_8} from "@rheo-fm/src/market/interfaces/v1.8/IRheoViewV1_8.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {BuyCreditMarket, BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {SellCreditMarket, SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {VERSION} from "@rheo-fm/src/market/interfaces/IRheo.sol";

/// @title RheoView
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice View methods for the Rheo protocol
abstract contract RheoView is RheoStorage, ReentrancyGuardUpgradeableWithViewModifier, IRheoView {
    using OfferLibrary for FixedMaturityLimitOrder;
    using OfferLibrary for State;
    using LoanLibrary for DebtPosition;
    using LoanLibrary for CreditPosition;
    using LoanLibrary for State;
    using RiskLibrary for State;
    using AccountingLibrary for State;
    using UpdateConfig for State;

    /// @inheritdoc IRheoView
    function collateralRatio(address user) external view returns (uint256) {
        return state.collateralRatio(user);
    }

    /// @inheritdoc IRheoView
    function debtTokenAmountToCollateralTokenAmount(uint256 amount) external view returns (uint256) {
        return state.debtTokenAmountToCollateralTokenAmount(amount);
    }

    /// @inheritdoc IRheoView
    function feeConfig() external view returns (InitializeFeeConfigParams memory) {
        return state.feeConfigParams();
    }

    /// @inheritdoc IRheoView
    function riskConfig() external view returns (InitializeRiskConfigParams memory) {
        return state.riskConfigParams();
    }

    /// @inheritdoc IRheoView
    function oracle() external view returns (InitializeOracleParams memory) {
        return state.oracleParams();
    }

    /// @inheritdoc IRheoView
    function data() external view returns (DataView memory) {
        return DataView({
            nextDebtPositionId: state.data.nextDebtPositionId,
            nextCreditPositionId: state.data.nextCreditPositionId,
            underlyingCollateralToken: state.data.underlyingCollateralToken,
            underlyingBorrowToken: state.data.underlyingBorrowToken,
            variablePool: state.data.variablePool,
            collateralToken: state.data.collateralToken,
            borrowTokenVault: state.data.borrowTokenVault,
            debtToken: state.data.debtToken
        });
    }

    /// @inheritdoc IRheoView
    /// @dev Changed in v1.8.4 to remove nonReentrantView for contract size limit optimization
    function getUserView(address user) external view returns (UserView memory) {
        return UserView({
            user: state.data.users[user],
            account: user,
            collateralTokenBalance: state.data.collateralToken.balanceOf(user),
            borrowTokenBalance: state.data.borrowTokenVault.balanceOf(user),
            debtBalance: state.data.debtToken.balanceOf(user)
        });
    }

    /// @inheritdoc IRheoViewV1_8
    function getUserDefinedCopyLimitOrderConfigs(address user)
        external
        view
        returns (CopyLimitOrderConfig memory, CopyLimitOrderConfig memory)
    {
        return (
            state.data.usersCopyLimitOrderConfigs[user].copyLoanOfferConfig,
            state.data.usersCopyLimitOrderConfigs[user].copyBorrowOfferConfig
        );
    }

    /// @inheritdoc IRheoView
    function getDebtPosition(uint256 debtPositionId) external view returns (DebtPosition memory) {
        return state.getDebtPosition(debtPositionId);
    }

    /// @inheritdoc IRheoView
    function getCreditPosition(uint256 creditPositionId) external view returns (CreditPosition memory) {
        return state.getCreditPosition(creditPositionId);
    }

    /// @inheritdoc IRheoViewV1_8
    function getUserDefinedLoanOfferAPR(address lender, uint256 maturity) external view returns (uint256) {
        return state.getUserDefinedLoanOfferAPR(lender, maturity);
    }

    /// @inheritdoc IRheoViewV1_8
    function getUserDefinedBorrowOfferAPR(address borrower, uint256 maturity) external view returns (uint256) {
        return state.getUserDefinedBorrowOfferAPR(borrower, maturity);
    }

    /// @inheritdoc IRheoViewV1_8
    function getLoanOfferAPR(address user, uint256 collectionId, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256)
    {
        return state.getLoanOfferAPR(user, collectionId, rateProvider, maturity);
    }

    /// @inheritdoc IRheoViewV1_8
    function getBorrowOfferAPR(address user, uint256 collectionId, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256)
    {
        return state.getBorrowOfferAPR(user, collectionId, rateProvider, maturity);
    }

    /// @inheritdoc IRheoViewV1_8
    function isUserDefinedLimitOrdersNull(address user)
        external
        view
        returns (bool isLoanOfferNull, bool isBorrowOfferNull)
    {
        return (state.data.users[user].loanOffer.isNull(), state.data.users[user].borrowOffer.isNull());
    }

    /// @inheritdoc IRheoView
    function getBuyCreditMarketSwapData(BuyCreditMarketParams memory params)
        external
        view
        returns (BuyCreditMarket.SwapDataBuyCreditMarket memory)
    {
        return BuyCreditMarket.getSwapData(state, params);
    }

    /// @inheritdoc IRheoView
    function getSellCreditMarketSwapData(SellCreditMarketParams memory params)
        external
        view
        returns (SellCreditMarket.SwapDataSellCreditMarket memory)
    {
        return SellCreditMarket.getSwapData(state, params);
    }

    /// @inheritdoc IRheoView
    function extSload(bytes32 key) external view returns (bytes32 result) {
        assembly {
            result := sload(key)
        }
    }

    /// @inheritdoc IRheoView
    function version() public pure returns (string memory) {
        return VERSION;
    }
}
