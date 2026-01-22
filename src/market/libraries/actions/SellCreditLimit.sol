// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {State} from "@src/market/SizeStorage.sol";

import {Action} from "@src/factory/libraries/Authorization.sol";
import {Errors} from "@src/market/libraries/Errors.sol";
import {Events} from "@src/market/libraries/Events.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@src/market/libraries/OfferLibrary.sol";

struct SellCreditLimitParams {
    // The fixed maturities of the borrow offer
    uint256[] maturities;
    // The APRs for each maturity
    uint256[] aprs;
}

struct SellCreditLimitOnBehalfOfParams {
    // The parameters for the sell credit limit
    SellCreditLimitParams params;
    // The account to set the sell credit limit order for
    address onBehalfOf;
}

/// @title SellCreditLimit
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Contains the logic for selling credit (borrowing) as a limit order
library SellCreditLimit {
    using OfferLibrary for FixedMaturityLimitOrder;

    /// @notice Validates the input parameters for selling credit as a limit order
    /// @param state The state
    /// @param externalParams The input parameters for selling credit as a limit order
    function validateSellCreditLimit(State storage state, SellCreditLimitOnBehalfOfParams memory externalParams)
        external
        view
    {
        SellCreditLimitParams memory params = externalParams.params;
        address onBehalfOf = externalParams.onBehalfOf;

        FixedMaturityLimitOrder memory borrowOffer =
            FixedMaturityLimitOrder({maturities: params.maturities, aprs: params.aprs});

        // validate msg.sender
        if (!state.data.sizeFactory.isAuthorized(msg.sender, onBehalfOf, Action.SELL_CREDIT_LIMIT)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.SELL_CREDIT_LIMIT));
        }

        // a null offer mean clearing their limit order
        if (!borrowOffer.isNull()) {
            // validate borrowOffer
            borrowOffer.validateLimitOrder(
                state.riskConfig.maturities, state.riskConfig.minTenor, state.riskConfig.maxTenor
            );
        }
    }

    /// @notice Executes the selling of credit as a limit order
    /// @param state The state
    /// @param externalParams The input parameters for selling credit as a limit order
    /// @dev A null offer means clearing a user's borrow limit order
    function executeSellCreditLimit(State storage state, SellCreditLimitOnBehalfOfParams memory externalParams)
        external
    {
        SellCreditLimitParams memory params = externalParams.params;
        address onBehalfOf = externalParams.onBehalfOf;

        emit Events.SellCreditLimit(msg.sender, onBehalfOf, params.maturities, params.aprs);

        state.data.users[onBehalfOf].borrowOffer =
            FixedMaturityLimitOrder({maturities: params.maturities, aprs: params.aprs});
    }
}
