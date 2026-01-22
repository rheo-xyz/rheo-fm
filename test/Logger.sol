// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Size} from "@src/market/Size.sol";
import {UserView} from "@src/market/SizeView.sol";
import {
    CREDIT_POSITION_ID_START,
    CreditPosition,
    DEBT_POSITION_ID_START,
    DebtPosition,
    LoanLibrary
} from "@src/market/libraries/LoanLibrary.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@src/market/libraries/OfferLibrary.sol";

import {console2 as console} from "forge-std/console2.sol";

abstract contract Logger {
    using LoanLibrary for DebtPosition;
    using OfferLibrary for FixedMaturityLimitOrder;

    function _log(UserView memory userView) internal pure {
        console.log("account", userView.account);
        if (!userView.user.loanOffer.isNull()) {
            for (uint256 i = 0; i < userView.user.loanOffer.aprs.length; i++) {
                console.log("user.loanOffer.maturities[]", userView.user.loanOffer.maturities[i]);
                console.log("user.loanOffer.aprs[]", userView.user.loanOffer.aprs[i]);
            }
        }
        if (!userView.user.borrowOffer.isNull()) {
            for (uint256 i = 0; i < userView.user.borrowOffer.aprs.length; i++) {
                console.log("user.borrowOffer.maturities[]", userView.user.borrowOffer.maturities[i]);
                console.log("user.borrowOffer.aprs[]", userView.user.borrowOffer.aprs[i]);
            }
        }
        console.log("collateralBalance", userView.collateralTokenBalance);
        console.log("borrowTokenBalance", userView.borrowTokenBalance);
        console.log("debtBalance", userView.debtBalance);
    }

    function _log(DebtPosition memory debtPosition) internal pure {
        console.log("borrower", debtPosition.borrower);
        console.log("futureValue", debtPosition.futureValue);
        console.log("dueDate", debtPosition.dueDate);
    }

    function _log(CreditPosition memory creditPosition) internal pure {
        console.log("lender", creditPosition.lender);
        console.log("forSale", creditPosition.forSale);
        console.log("credit", creditPosition.credit);
        console.log("debtPositionId", creditPosition.debtPositionId);
    }

    function _log(Size size) internal view {
        uint256 debtPositionsCount = size.data().nextDebtPositionId - DEBT_POSITION_ID_START;
        uint256 creditPositionsCount = size.data().nextCreditPositionId - CREDIT_POSITION_ID_START;
        uint256 totalDebt;
        uint256 totalCredit;
        for (uint256 i = 0; i < debtPositionsCount; ++i) {
            uint256 debtPositionId = DEBT_POSITION_ID_START + i;
            totalDebt += size.getDebtPosition(debtPositionId).futureValue;
            console.log(string.concat("D[", Strings.toString(i), "]"), size.getDebtPosition(debtPositionId).futureValue);
        }
        console.log("D   ", totalDebt);
        for (uint256 i = 0; i < creditPositionsCount; ++i) {
            uint256 creditPositionId = CREDIT_POSITION_ID_START + i;
            totalCredit += size.getCreditPosition(creditPositionId).credit;
            console.log(string.concat("C[", Strings.toString(i), "]"), size.getCreditPosition(creditPositionId).credit);
        }
        console.log("C   ", totalCredit);
    }
}
