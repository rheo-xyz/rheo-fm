// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {State} from "@rheo-fm/src/market/RheoStorage.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Events} from "@rheo-fm/src/market/libraries/Events.sol";
import {Action} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

struct BuyCreditLimitParams {
    // The fixed maturities of the loan offer
    uint256[] maturities;
    // The APRs for each maturity
    uint256[] aprs;
}

struct BuyCreditLimitOnBehalfOfParams {
    // The parameters for the buy credit limit
    BuyCreditLimitParams params;
    // The account to set the buy credit limit order for
    address onBehalfOf;
}

/// @title BuyCreditLimit
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Contains the logic for buying credit (lending) as a limit order
library BuyCreditLimit {
    using OfferLibrary for FixedMaturityLimitOrder;

    /// @notice Validates the input parameters for buying credit as a limit order
    /// @param state The state
    /// @param externalParams The input parameters for buying credit as a limit order
    function validateBuyCreditLimit(State storage state, BuyCreditLimitOnBehalfOfParams memory externalParams)
        external
        view
    {
        BuyCreditLimitParams memory params = externalParams.params;
        address onBehalfOf = externalParams.onBehalfOf;

        FixedMaturityLimitOrder memory loanOffer =
            FixedMaturityLimitOrder({maturities: params.maturities, aprs: params.aprs});

        // validate msg.sender
        if (!state.data.sizeFactory.isAuthorized(msg.sender, onBehalfOf, Action.BUY_CREDIT_LIMIT)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.BUY_CREDIT_LIMIT));
        }

        // a null offer mean clearing their limit order
        if (!loanOffer.isNull()) {
            // validate loanOffer
            loanOffer.validateLimitOrder(
                state.riskConfig.maturities, state.riskConfig.minTenor, state.riskConfig.maxTenor
            );
        }
    }

    /// @notice Executes the buying of credit as a limit order
    /// @param state The state
    /// @param externalParams The input parameters for buying credit as a limit order
    /// @dev A null offer means clearing a user's loan limit order
    function executeBuyCreditLimit(State storage state, BuyCreditLimitOnBehalfOfParams memory externalParams)
        external
    {
        BuyCreditLimitParams memory params = externalParams.params;
        address onBehalfOf = externalParams.onBehalfOf;

        emit Events.BuyCreditLimit(msg.sender, onBehalfOf, params.maturities, params.aprs);

        state.data.users[onBehalfOf].loanOffer =
            FixedMaturityLimitOrder({maturities: params.maturities, aprs: params.aprs});
    }
}
