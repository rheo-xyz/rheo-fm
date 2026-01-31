// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {State} from "@src/market/SizeStorage.sol";

import {Claim, ClaimParams} from "@src/market/libraries/actions/Claim.sol";
import {Liquidate, LiquidateParams} from "@src/market/libraries/actions/Liquidate.sol";
import {UpdateConfig, UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

import {Withdraw, WithdrawOnBehalfOfParams, WithdrawParams} from "@src/market/libraries/actions/Withdraw.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {Errors} from "@src/market/libraries/Errors.sol";
import {Events} from "@src/market/libraries/Events.sol";

struct MarketShutdownParams {
    uint256[] debtPositionIdsToForceLiquidate;
    uint256[] creditPositionIdsToClaim;
    address[] usersToForceWithdraw;
    bool shouldCheckSupply;
}

/// @title MarketShutdown
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Contains the logic for shutting down the market
library MarketShutdown {
    /// @notice Validates the market shutdown parameters
    function validateMarketShutdown(State storage, MarketShutdownParams calldata) external pure {
        // validation is done at execution
    }

    /// @notice Executes the market shutdown
    /// @dev Set liquidation reward to 0 to not punish borrowers
    /// @dev Claim liquidated positions to move repaid funds to lenders
    /// @dev Force withdraw collateral from users to themselves
    /// @dev Optionally check that the debt and collateral of the system are 0
    /// @param state The state of the protocol
    /// @param params The input parameters for shutting down the market
    function executeMarketShutdown(State storage state, MarketShutdownParams memory params) public {
        emit Events.MarketShutdown(
            msg.sender,
            params.debtPositionIdsToForceLiquidate,
            params.creditPositionIdsToClaim,
            params.usersToForceWithdraw
        );

        string[4] memory keys = [
            "collateralProtocolPercent",
            "liquidationRewardPercent",
            "overdueCollateralProtocolPercent",
            "overdueLiquidationRewardPercent"
        ];
        for (uint256 i = 0; i < keys.length; i++) {
            UpdateConfigParams memory updateConfigParams = UpdateConfigParams({key: keys[i], value: 0});
            UpdateConfig.validateUpdateConfig(state, updateConfigParams);
            UpdateConfig.executeUpdateConfig(state, updateConfigParams);
        }
        for (uint256 i = 0; i < params.debtPositionIdsToForceLiquidate.length; i++) {
            LiquidateParams memory liquidateParams = LiquidateParams({
                debtPositionId: params.debtPositionIdsToForceLiquidate[i],
                minimumCollateralProfit: 0,
                deadline: block.timestamp
            });
            // Liquidate.validateLiquidate(state, liquidateParams); // skip validation to allow liquidations of all positions
            uint256 liquidatorProfitCollateralToken = Liquidate.executeLiquidate(state, liquidateParams);
            Liquidate.validateMinimumCollateralProfit(state, liquidateParams, liquidatorProfitCollateralToken);
        }
        for (uint256 i = 0; i < params.creditPositionIdsToClaim.length; i++) {
            ClaimParams memory claimParams = ClaimParams({creditPositionId: params.creditPositionIdsToClaim[i]});
            Claim.validateClaim(state, claimParams);
            Claim.executeClaim(state, claimParams);
        }
        for (uint256 i = 0; i < params.usersToForceWithdraw.length; i++) {
            WithdrawOnBehalfOfParams memory withdrawParams = WithdrawOnBehalfOfParams({
                params: WithdrawParams({
                    token: address(state.data.underlyingCollateralToken),
                    amount: type(uint256).max,
                    to: params.usersToForceWithdraw[i]
                }),
                onBehalfOf: params.usersToForceWithdraw[i]
            });
            // Withdraw.validateWithdraw(state, withdrawParams); // skip validation to allow force withdraw
            Withdraw.executeWithdraw(state, withdrawParams);
        }

        if (params.shouldCheckSupply) {
            if (state.data.debtToken.totalSupply() > 0) {
                revert Errors.INVALID_AMOUNT(state.data.debtToken.totalSupply());
            }
            if (state.data.collateralToken.totalSupply() > 0) {
                revert Errors.INVALID_AMOUNT(state.data.collateralToken.totalSupply());
            }
        }
    }
}
