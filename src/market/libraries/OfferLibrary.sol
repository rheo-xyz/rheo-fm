// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {State} from "@src/market/SizeStorage.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {Errors} from "@src/market/libraries/Errors.sol";
import {Math} from "@src/market/libraries/Math.sol";

struct FixedMaturityLimitOrder {
    // Sorted list of fixed maturity timestamps
    uint256[] maturities;
    // APRs for each maturity
    uint256[] aprs;
}

struct CopyLimitOrderConfig {
    // the minimum tenor of the copied offer
    uint256 minTenor;
    // the maximum tenor of the copied offer
    uint256 maxTenor;
    // the minimum APR of the copied offer
    uint256 minAPR;
    // the maximum APR of the copied offer
    uint256 maxAPR;
    // the offset APR relative to the copied offer
    int256 offsetAPR;
}

/// @title OfferLibrary
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
library OfferLibrary {
    using EnumerableSet for EnumerableSet.UintSet;
    /// @notice Check if the limit order is null
    /// @param self The limit order
    /// @return True if the limit order is null, false otherwise

    function isNull(FixedMaturityLimitOrder memory self) internal pure returns (bool) {
        return self.maturities.length == 0 && self.aprs.length == 0;
    }

    /// @notice Check if the copy limit order is null
    /// @param self The copy limit order
    /// @return True if the copy limit order is null, false otherwise
    function isNull(CopyLimitOrderConfig memory self) internal pure returns (bool) {
        return self.minTenor == 0 && self.maxTenor == 0 && self.minAPR == 0 && self.maxAPR == 0 && self.offsetAPR == 0;
    }

    /// @notice Validate the limit order
    /// @dev Validates that limit order maturities are strictly increasing and within minTenor/maxTenor.
    /// @param self The limit order
    /// @param maturities The allowed maturities set
    /// @param minTenor The minimum tenor
    /// @param maxTenor The maximum tenor
    function validateLimitOrder(
        FixedMaturityLimitOrder memory self,
        EnumerableSet.UintSet storage maturities,
        uint256 minTenor,
        uint256 maxTenor
    ) internal view {
        if (self.maturities.length == 0 || self.aprs.length == 0) {
            revert Errors.NULL_ARRAY();
        }
        if (self.maturities.length != self.aprs.length) {
            revert Errors.ARRAY_LENGTHS_MISMATCH();
        }

        if (maturities.length() == 0) {
            revert Errors.NULL_ARRAY();
        }

        uint256 lastMaturity = 0;
        for (uint256 i = 0; i < self.maturities.length; i++) {
            uint256 maturity = self.maturities[i];
            if (maturity <= lastMaturity) {
                revert Errors.MATURITIES_NOT_STRICTLY_INCREASING();
            }
            if (maturity <= block.timestamp) {
                revert Errors.PAST_MATURITY(maturity);
            }
            uint256 tenor = maturity - block.timestamp;
            if (tenor < minTenor || tenor > maxTenor) {
                revert Errors.MATURITY_OUT_OF_RANGE(maturity, minTenor, maxTenor);
            }
            if (!maturities.contains(maturity)) {
                revert Errors.INVALID_MATURITY(maturity);
            }
            lastMaturity = maturity;
        }
    }

    /// @notice Validate the copy limit order configs
    /// @param copyLoanOfferConfig The copy loan offer config
    /// @param copyBorrowOfferConfig The copy borrow offer config
    /// @dev assert min <= max and no arbitrageable setup
    function validateCopyLimitOrderConfigs(
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig
    ) internal pure {
        if (copyLoanOfferConfig.minTenor > copyLoanOfferConfig.maxTenor) {
            revert Errors.INVALID_TENOR_RANGE(copyLoanOfferConfig.minTenor, copyLoanOfferConfig.maxTenor);
        }
        if (copyLoanOfferConfig.minAPR > copyLoanOfferConfig.maxAPR) {
            revert Errors.INVALID_APR_RANGE(copyLoanOfferConfig.minAPR, copyLoanOfferConfig.maxAPR);
        }
        if (copyBorrowOfferConfig.minTenor > copyBorrowOfferConfig.maxTenor) {
            revert Errors.INVALID_TENOR_RANGE(copyBorrowOfferConfig.minTenor, copyBorrowOfferConfig.maxTenor);
        }
        if (copyBorrowOfferConfig.minAPR > copyBorrowOfferConfig.maxAPR) {
            revert Errors.INVALID_APR_RANGE(copyBorrowOfferConfig.minAPR, copyBorrowOfferConfig.maxAPR);
        }
        if (
            copyBorrowOfferConfig.minAPR > copyLoanOfferConfig.maxAPR
                && (copyBorrowOfferConfig.maxTenor >= copyLoanOfferConfig.minTenor)
                && (copyLoanOfferConfig.maxTenor >= copyBorrowOfferConfig.minTenor)
        ) {
            revert Errors.INVALID_OFFER_CONFIGS(
                copyBorrowOfferConfig.minTenor,
                copyBorrowOfferConfig.maxTenor,
                copyBorrowOfferConfig.minAPR,
                copyBorrowOfferConfig.maxAPR,
                copyLoanOfferConfig.minTenor,
                copyLoanOfferConfig.maxTenor,
                copyLoanOfferConfig.minAPR,
                copyLoanOfferConfig.maxAPR
            );
        }
    }

    function getUserDefinedBorrowOfferAPR(State storage state, address user, uint256 maturity)
        internal
        view
        returns (uint256 apr)
    {
        return getUserDefinedLimitOrderAPR(user, state.data.users[user].borrowOffer, maturity);
    }

    function getUserDefinedLoanOfferAPR(State storage state, address user, uint256 maturity)
        internal
        view
        returns (uint256 apr)
    {
        return getUserDefinedLimitOrderAPR(user, state.data.users[user].loanOffer, maturity);
    }

    function getUserDefinedLimitOrderAPR(address user, FixedMaturityLimitOrder memory limitOrder, uint256 maturity)
        internal
        view
        returns (uint256 apr)
    {
        if (maturity == 0) {
            revert Errors.NULL_MATURITY();
        }
        if (isNull(limitOrder)) {
            revert Errors.INVALID_OFFER(user);
        }
        if (maturity <= block.timestamp) {
            revert Errors.PAST_MATURITY(maturity);
        }

        (uint256 low, uint256 high) = Math.binarySearch(limitOrder.maturities, maturity);
        if (low == type(uint256).max || low != high) {
            revert Errors.INVALID_MATURITY(maturity);
        }

        return limitOrder.aprs[low];
    }

    /// @notice Get the APR by maturity of a loan offer
    /// @param state The state
    /// @param user The user
    /// @param collectionId The collection id
    /// @param rateProvider The rate provider
    /// @param maturity The maturity
    /// @return apr The APR
    function getLoanOfferAPR(
        State storage state,
        address user,
        uint256 collectionId,
        address rateProvider,
        uint256 maturity
    ) public view returns (uint256 apr) {
        return state.data.sizeFactory.getLoanOfferAPR(user, collectionId, ISize(address(this)), rateProvider, maturity);
    }

    /// @notice Get the absolute rate per tenor of a loan offer
    /// @dev Caller must validate maturity before calling to avoid Panic. This is done in `validateSellCreditMarket`
    /// @param state The state
    /// @param user The user
    /// @param collectionId The collection id
    /// @param rateProvider The rate provider
    /// @param maturity The maturity
    /// @return ratePerTenor The absolute rate
    function getLoanOfferRatePerTenor(
        State storage state,
        address user,
        uint256 collectionId,
        address rateProvider,
        uint256 maturity
    ) internal view returns (uint256 ratePerTenor) {
        uint256 tenor = maturity - block.timestamp;
        uint256 apr = getLoanOfferAPR(state, user, collectionId, rateProvider, maturity);
        ratePerTenor = Math.aprToRatePerTenor(apr, tenor);
    }

    /// @notice Get the APR by maturity of a borrow offer
    /// @param state The state
    /// @param user The user
    /// @param collectionId The collection id
    /// @param rateProvider The rate provider
    /// @param maturity The maturity
    /// @return apr The APR
    function getBorrowOfferAPR(
        State storage state,
        address user,
        uint256 collectionId,
        address rateProvider,
        uint256 maturity
    ) public view returns (uint256 apr) {
        return
            state.data.sizeFactory.getBorrowOfferAPR(user, collectionId, ISize(address(this)), rateProvider, maturity);
    }

    /// @notice Get the absolute rate per tenor of a borrow offer
    /// @dev Caller must validate maturity before calling to avoid Panic. This is done in `validateBuyCreditMarket`
    /// @param state The state
    /// @param user The user
    /// @param collectionId The collection id
    /// @param rateProvider The rate provider
    /// @param maturity The maturity
    /// @return ratePerTenor The absolute rate
    function getBorrowOfferRatePerTenor(
        State storage state,
        address user,
        uint256 collectionId,
        address rateProvider,
        uint256 maturity
    ) internal view returns (uint256 ratePerTenor) {
        uint256 tenor = maturity - block.timestamp;
        uint256 apr = getBorrowOfferAPR(state, user, collectionId, rateProvider, maturity);
        ratePerTenor = Math.aprToRatePerTenor(apr, tenor);
    }

    function isBorrowAPRLowerThanLoanOfferAPRs(State storage state, address user, uint256 borrowAPR, uint256 maturity)
        internal
        view
        returns (bool)
    {
        return state.data.sizeFactory.isBorrowAPRLowerThanLoanOfferAPRs(user, borrowAPR, ISize(address(this)), maturity);
    }

    function isLoanAPRGreaterThanBorrowOfferAPRs(State storage state, address user, uint256 loanAPR, uint256 maturity)
        internal
        view
        returns (bool)
    {
        return state.data.sizeFactory.isLoanAPRGreaterThanBorrowOfferAPRs(user, loanAPR, ISize(address(this)), maturity);
    }
}
