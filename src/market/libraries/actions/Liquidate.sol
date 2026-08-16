// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@rheo-fm/src/market/libraries/Math.sol";

import {PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";

import {DebtPosition, LoanLibrary, LoanStatus} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {AccountingLibrary} from "@rheo-fm/src/market/libraries/AccountingLibrary.sol";
import {CollateralBasketLibrary} from "@rheo-fm/src/market/libraries/CollateralBasketLibrary.sol";
import {RiskLibrary} from "@rheo-fm/src/market/libraries/RiskLibrary.sol";

import {CollateralAsset, State} from "@rheo-fm/src/market/RheoStorage.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Events} from "@rheo-fm/src/market/libraries/Events.sol";

struct LiquidateParams {
    // The debt position ID to liquidate
    uint256 debtPositionId;
    // The minimum liquidator profit expected, in borrow token base units
    uint256 minimumCollateralProfitValue;
    // The deadline for the transaction
    uint256 deadline;
    // The seize breakdown, aligned with the collateral asset registry
    // An empty array seizes pro-rata across all collateral assets
    uint256[] seizeCollateralAmounts;
}

/// @title Liquidate
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Contains the logic for liquidating a debt position
library Liquidate {
    using LoanLibrary for DebtPosition;
    using LoanLibrary for State;
    using RiskLibrary for State;
    using AccountingLibrary for State;
    using CollateralBasketLibrary for State;

    struct LiquidateVars {
        uint256 collateralProtocolPercent;
        uint256 liquidationRewardPercent;
        uint256 assignedValue;
        uint256 futureValue;
        uint256 entitlementValue;
        uint256 protocolProfitValue;
        uint256 remainingValue;
    }

    /// @notice Validates the input parameters for liquidating a debt position
    /// @param state The state
    function validateLiquidate(State storage state, LiquidateParams calldata params) external view {
        DebtPosition storage debtPosition = state.getDebtPosition(params.debtPositionId);

        // validate msg.sender
        // N/A

        // validate debtPositionId
        if (!state.isDebtPositionLiquidatable(params.debtPositionId)) {
            revert Errors.LOAN_NOT_LIQUIDATABLE(
                params.debtPositionId,
                state.collateralRatio(debtPosition.borrower),
                uint8(state.getLoanStatus(params.debtPositionId))
            );
        }

        // validate minimumCollateralProfitValue
        // N/A

        // validate deadline
        if (params.deadline < block.timestamp) {
            revert Errors.PAST_DEADLINE(params.deadline);
        }

        // validate seizeCollateralAmounts
        if (
            params.seizeCollateralAmounts.length != 0
                && params.seizeCollateralAmounts.length != state.data.collateralAssets.length
        ) {
            revert Errors.SEIZE_COLLATERAL_AMOUNTS_LENGTH_MISMATCH(
                state.data.collateralAssets.length, params.seizeCollateralAmounts.length
            );
        }
    }

    /// @notice Validates the minimum liquidator profit value expected by the liquidator
    /// @param params The input parameters for liquidating a debt position
    /// @param liquidatorProfitValue The realized liquidator profit, in borrow token base units
    function validateMinimumCollateralProfit(
        State storage,
        LiquidateParams calldata params,
        uint256 liquidatorProfitValue
    ) external pure {
        if (liquidatorProfitValue < params.minimumCollateralProfitValue) {
            revert Errors.LIQUIDATE_PROFIT_BELOW_MINIMUM_COLLATERAL_PROFIT(
                liquidatorProfitValue, params.minimumCollateralProfitValue
            );
        }
    }

    /// @notice Seizes the liquidator's entitlement from the borrower's basket
    /// @dev An empty `seizeCollateralAmounts` slices every asset pro-rata to the entitlement.
    ///      Otherwise the liquidator picks the breakdown, and the value taken, rounded up, must not exceed
    ///      the entitlement.
    /// @param state The state
    /// @param params The input parameters for liquidating a debt position
    /// @param borrower The borrower being liquidated
    /// @param entitlementValue The liquidator entitlement, in borrow token base units
    /// @return tokens The underlying collateral token addresses, aligned with the registry
    /// @return amounts The seized amounts, aligned with `tokens`
    /// @return liquidatorProfitValue The value of the seized collateral, rounded down
    function seizeCollateral(
        State storage state,
        LiquidateParams calldata params,
        address borrower,
        uint256 entitlementValue
    ) private returns (address[] memory tokens, uint256[] memory amounts, uint256 liquidatorProfitValue) {
        if (params.seizeCollateralAmounts.length == 0) {
            return state.transferProRata(
                borrower, msg.sender, entitlementValue, CollateralBasketLibrary.collateralValue(state, borrower)
            );
        }

        uint256 length = state.data.collateralAssets.length;
        tokens = new address[](length);
        amounts = new uint256[](length);

        uint256 seizedValueUp = 0;
        for (uint256 i = 0; i < length; i++) {
            CollateralAsset storage asset = state.data.collateralAssets[i];
            tokens[i] = address(asset.underlying);

            uint256 amount = params.seizeCollateralAmounts[i];
            if (amount == 0) {
                continue;
            }

            uint256 balance = asset.token.balanceOf(borrower);
            if (amount > balance) {
                revert Errors.NOT_ENOUGH_COLLATERAL(balance, amount);
            }

            amounts[i] = amount;
            seizedValueUp += state.assetValueUp(i, amount);
            liquidatorProfitValue += state.assetValueDown(i, amount);
        }

        if (seizedValueUp > entitlementValue) {
            revert Errors.SEIZED_VALUE_GREATER_THAN_ENTITLEMENT(seizedValueUp, entitlementValue);
        }

        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] != 0) {
                state.data.collateralAssets[i].token.transferFrom(borrower, msg.sender, amounts[i]);
            }
        }
    }

    /// @notice Executes the liquidation of a debt position
    /// @param state The state
    /// @param params The input parameters for liquidating a debt position
    /// @return liquidatorProfitValue The liquidator profit, in borrow token base units
    function executeLiquidate(State storage state, LiquidateParams calldata params)
        external
        returns (uint256 liquidatorProfitValue)
    {
        DebtPosition storage debtPosition = state.getDebtPosition(params.debtPositionId);

        emit Events.Liquidate(
            msg.sender,
            params.debtPositionId,
            params.minimumCollateralProfitValue,
            params.deadline,
            state.collateralRatio(debtPosition.borrower),
            uint8(state.getLoanStatus(params.debtPositionId))
        );

        LiquidateVars memory vars;
        vars.assignedValue = state.getDebtPositionAssignedCollateralValue(debtPosition);
        vars.futureValue = debtPosition.futureValue;

        // if the loan is both underwater and overdue, the protocol fee related to underwater liquidations takes precedence
        if (state.isUserUnderwater(debtPosition.borrower)) {
            vars.collateralProtocolPercent = state.feeConfig.collateralProtocolPercent;
            vars.liquidationRewardPercent = state.feeConfig.liquidationRewardPercent;
        } else {
            vars.collateralProtocolPercent = state.feeConfig.overdueCollateralProtocolPercent;
            vars.liquidationRewardPercent = state.data.overdueLiquidationRewardPercent;
        }

        // profitable liquidation
        if (vars.assignedValue > vars.futureValue) {
            uint256 liquidatorReward = Math.min(
                vars.assignedValue - vars.futureValue,
                Math.mulDivUp(vars.futureValue, vars.liquidationRewardPercent, PERCENT)
            );
            vars.entitlementValue = vars.futureValue + liquidatorReward;

            // the protocol earns a portion of the collateral remainder
            uint256 collateralRemainder = vars.assignedValue - vars.entitlementValue;

            // cap the collateral remainder to FV * (crLiquidation - 1)
            //   otherwise, the split for non-underwater overdue loans could be too much
            uint256 collateralRemainderCap =
                Math.mulDivDown(vars.futureValue, state.riskConfig.crLiquidation - PERCENT, PERCENT);

            collateralRemainder = Math.min(collateralRemainder, collateralRemainderCap);

            vars.protocolProfitValue = Math.mulDivDown(collateralRemainder, vars.collateralProtocolPercent, PERCENT);
        } else {
            // unprofitable liquidation
            vars.entitlementValue = vars.assignedValue;
        }

        state.data.borrowTokenVault.transferFrom(msg.sender, address(this), vars.futureValue);

        (address[] memory tokens, uint256[] memory liquidatorAmounts, uint256 profitValue) =
            seizeCollateral(state, params, debtPosition.borrower, vars.entitlementValue);
        liquidatorProfitValue = profitValue;

        // the protocol fee is sliced pro-rata from what is left after the liquidator seizure.
        // the remainder covers the fee by construction, but pro-rata seizure rounds each asset independently,
        // so the fee is clamped to the remainder rather than risking a revert on dust
        vars.remainingValue = CollateralBasketLibrary.collateralValue(state, debtPosition.borrower);
        (, uint256[] memory protocolAmounts,) = state.transferProRata(
            debtPosition.borrower,
            state.feeConfig.feeRecipient,
            Math.min(vars.protocolProfitValue, vars.remainingValue),
            vars.remainingValue
        );

        emit Events.LiquidateCollateralSeized(params.debtPositionId, tokens, liquidatorAmounts, protocolAmounts);

        debtPosition.liquidityIndexAtRepayment = state.data.borrowTokenVault.liquidityIndex();
        state.repayDebt(params.debtPositionId, vars.futureValue);
    }
}
