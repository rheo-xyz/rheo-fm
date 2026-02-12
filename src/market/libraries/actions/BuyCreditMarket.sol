// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {State, User} from "@rheo-fm/src/market/RheoStorage.sol";

import {AccountingLibrary} from "@rheo-fm/src/market/libraries/AccountingLibrary.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Events} from "@rheo-fm/src/market/libraries/Events.sol";
import {CreditPosition, DebtPosition, LoanLibrary, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {RiskLibrary} from "@rheo-fm/src/market/libraries/RiskLibrary.sol";
import {Action} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

struct BuyCreditMarketParams {
    // The borrower
    // If creditPositionId is not RESERVED_ID, this value is ignored and the owner of the existing credit is used
    address borrower;
    // The credit position ID to buy
    // If RESERVED_ID, a new credit position will be created
    uint256 creditPositionId;
    // The amount of credit to buy
    uint256 amount;
    // The maturity of the loan
    // If creditPositionId is not RESERVED_ID, this value is ignored and the maturity of the existing loan is used
    uint256 maturity;
    // The deadline for the transaction
    uint256 deadline;
    // The minimum APR for the loan
    uint256 minAPR;
    // Whether amount means cash or credit
    bool exactAmountIn;
    // The collection Id (introduced in v1.8)
    // If collectionId is RESERVED_ID, selects the user-defined offer
    uint256 collectionId;
    // The rate provider (introduced in v1.8)
    // If collectionId is RESERVED_ID, selects the user-defined offer
    address rateProvider;
}

struct BuyCreditMarketOnBehalfOfParams {
    // The parameters for the buy credit market order
    BuyCreditMarketParams params;
    // The account to transfer the cash from
    address onBehalfOf;
    // The account to transfer the credit to
    address recipient;
}

/// @title BuyCreditMarket
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Contains the logic for buying credit (lending) as a market order
library BuyCreditMarket {
    using OfferLibrary for FixedMaturityLimitOrder;
    using OfferLibrary for State;
    using AccountingLibrary for State;
    using LoanLibrary for State;
    using LoanLibrary for DebtPosition;
    using LoanLibrary for CreditPosition;
    using RiskLibrary for State;

    struct SwapDataBuyCreditMarket {
        CreditPosition creditPosition;
        address borrower;
        uint256 creditAmountOut;
        uint256 cashAmountIn;
        uint256 swapFee;
        uint256 fragmentationFee;
        uint256 maturity;
    }

    /// @notice Validates the input parameters for buying credit as a market order
    /// @param state The state of the protocol
    /// @param externalParams The input parameters for buying credit as a market order
    function validateBuyCreditMarket(State storage state, BuyCreditMarketOnBehalfOfParams calldata externalParams)
        external
        view
    {
        BuyCreditMarketParams memory params = externalParams.params;
        address onBehalfOf = externalParams.onBehalfOf;
        address recipient = externalParams.recipient;

        address borrower;
        uint256 maturity;

        // validate msg.sender
        if (!state.data.sizeFactory.isAuthorized(msg.sender, onBehalfOf, Action.BUY_CREDIT_MARKET)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.BUY_CREDIT_MARKET));
        }

        // validate recipient
        if (recipient == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        // validate creditPositionId
        if (params.creditPositionId == RESERVED_ID) {
            borrower = params.borrower;
            maturity = params.maturity;
        } else {
            CreditPosition storage creditPosition = state.getCreditPosition(params.creditPositionId);
            DebtPosition storage debtPosition = state.getDebtPositionByCreditPositionId(params.creditPositionId);
            if (!state.isCreditPositionTransferrable(params.creditPositionId)) {
                revert Errors.CREDIT_POSITION_NOT_TRANSFERRABLE(
                    params.creditPositionId,
                    uint8(state.getLoanStatus(params.creditPositionId)),
                    state.collateralRatio(debtPosition.borrower)
                );
            }
            User storage user = state.data.users[creditPosition.lender];
            if (user.allCreditPositionsForSaleDisabled || !creditPosition.forSale) {
                revert Errors.CREDIT_NOT_FOR_SALE(params.creditPositionId);
            }

            borrower = creditPosition.lender;
            maturity = debtPosition.dueDate;
        }

        // validate borrower
        if (borrower == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        // validate amount
        if (params.amount == 0) {
            revert Errors.NULL_AMOUNT();
        }

        // validate maturity
        state.validateMaturity(maturity);

        // validate deadline
        if (params.deadline < block.timestamp) {
            revert Errors.PAST_DEADLINE(params.deadline);
        }

        // validate minAPR
        uint256 borrowAPR = state.getBorrowOfferAPR(borrower, params.collectionId, params.rateProvider, maturity);
        if (borrowAPR < params.minAPR) {
            revert Errors.APR_LOWER_THAN_MIN_APR(borrowAPR, params.minAPR);
        }

        // validate exactAmountIn
        // N/A

        // validate inverted offers
        if (!state.isBorrowAPRLowerThanLoanOfferAPRs(borrower, borrowAPR, maturity)) {
            revert Errors.INVERTED_OFFERS(borrower, maturity);
        }

        // validate collectionId
        // validate rateProvider
        // these are validated in `CollectionsManager`
    }

    /// @notice Gets the swap data for buying credit as a market order
    /// @param state The state
    /// @param params The input parameters for buying credit as a market order
    /// @return swapData The swap data for buying credit as a market order
    function getSwapData(State storage state, BuyCreditMarketParams memory params)
        public
        view
        returns (SwapDataBuyCreditMarket memory swapData)
    {
        if (params.creditPositionId == RESERVED_ID) {
            swapData.borrower = params.borrower;
            swapData.maturity = params.maturity;
        } else {
            DebtPosition storage debtPosition = state.getDebtPositionByCreditPositionId(params.creditPositionId);
            swapData.creditPosition = state.getCreditPosition(params.creditPositionId);

            swapData.borrower = swapData.creditPosition.lender;
            swapData.maturity = debtPosition.dueDate;
        }

        uint256 ratePerTenor = state.getBorrowOfferRatePerTenor(
            swapData.borrower, params.collectionId, params.rateProvider, swapData.maturity
        );
        uint256 tenor = swapData.maturity - block.timestamp;

        if (params.exactAmountIn) {
            swapData.cashAmountIn = params.amount;
            (swapData.creditAmountOut, swapData.swapFee, swapData.fragmentationFee) = state.getCreditAmountOut({
                cashAmountIn: swapData.cashAmountIn,
                maxCashAmountIn: params.creditPositionId == RESERVED_ID
                    ? swapData.cashAmountIn
                    : Math.mulDivUp(swapData.creditPosition.credit, PERCENT, PERCENT + ratePerTenor),
                maxCredit: params.creditPositionId == RESERVED_ID
                    ? Math.mulDivDown(swapData.cashAmountIn, PERCENT + ratePerTenor, PERCENT)
                    : swapData.creditPosition.credit,
                ratePerTenor: ratePerTenor,
                tenor: tenor
            });
        } else {
            swapData.creditAmountOut = params.amount;
            (swapData.cashAmountIn, swapData.swapFee, swapData.fragmentationFee) = state.getCashAmountIn({
                creditAmountOut: swapData.creditAmountOut,
                maxCredit: params.creditPositionId == RESERVED_ID
                    ? swapData.creditAmountOut
                    : swapData.creditPosition.credit,
                ratePerTenor: ratePerTenor,
                tenor: tenor
            });
        }
    }

    /// @notice Executes the buying of credit as a market order
    /// @param state The state of the protocol
    /// @param externalParams The input parameters for buying credit as a market order
    function executeBuyCreditMarket(State storage state, BuyCreditMarketOnBehalfOfParams calldata externalParams)
        external
    {
        BuyCreditMarketParams memory params = externalParams.params;
        address onBehalfOf = externalParams.onBehalfOf;
        address recipient = externalParams.recipient;

        emit Events.BuyCreditMarket(
            msg.sender,
            onBehalfOf,
            params.borrower,
            recipient,
            params.creditPositionId,
            params.amount,
            params.maturity,
            params.deadline,
            params.minAPR,
            params.exactAmountIn,
            params.collectionId,
            params.rateProvider
        );

        SwapDataBuyCreditMarket memory swapData = getSwapData(state, params);

        if (params.creditPositionId == RESERVED_ID) {
            // slither-disable-next-line unused-return
            state.createDebtAndCreditPositions({
                lender: recipient,
                borrower: swapData.borrower,
                futureValue: swapData.creditAmountOut,
                dueDate: swapData.maturity
            });
        } else {
            state.createCreditPosition({
                exitCreditPositionId: params.creditPositionId,
                lender: recipient,
                credit: swapData.creditAmountOut,
                forSale: true
            });
        }

        state.data.borrowTokenVault.transferFrom(
            onBehalfOf, swapData.borrower, swapData.cashAmountIn - swapData.swapFee - swapData.fragmentationFee
        );
        state.data.borrowTokenVault.transferFrom(
            onBehalfOf, state.feeConfig.feeRecipient, swapData.swapFee + swapData.fragmentationFee
        );

        uint256 exitCreditPositionId =
            params.creditPositionId == RESERVED_ID ? state.data.nextCreditPositionId - 1 : params.creditPositionId;

        emit Events.SwapData(
            exitCreditPositionId,
            swapData.borrower,
            recipient,
            swapData.creditAmountOut,
            swapData.cashAmountIn,
            swapData.cashAmountIn - swapData.swapFee - swapData.fragmentationFee,
            swapData.swapFee,
            swapData.fragmentationFee,
            swapData.maturity
        );
    }
}
