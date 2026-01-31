// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CopyLimitOrderConfig} from "@src/market/libraries/OfferLibrary.sol";

/// @title ISizeViewV1_8
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for the Size v1.8 view methods
interface ISizeViewV1_8 {
    /// @notice Get the APR for a user-defined loan offer
    /// @param lender The address of the lender
    /// @param tenor The tenor of the loan
    /// @return apr The APR
    function getUserDefinedLoanOfferAPR(address lender, uint256 tenor) external view returns (uint256);

    /// @notice Get the APR for a user-defined borrow offer
    /// @param borrower The address of the borrower
    /// @param tenor The tenor of the loan
    /// @return apr The APR
    function getUserDefinedBorrowOfferAPR(address borrower, uint256 tenor) external view returns (uint256);

    /// @notice Get the APR for a loan offer in a collection from a rate provider
    /// @param user The address of the user
    /// @param collectionId The ID of the collection
    /// @param rateProvider The address of the rate provider
    /// @param tenor The tenor of the loan
    /// @return apr The APR
    function getLoanOfferAPR(address user, uint256 collectionId, address rateProvider, uint256 tenor)
        external
        view
        returns (uint256);

    /// @notice Get the APR for a borrow offer in a collection from a rate provider
    /// @param user The address of the user
    /// @param collectionId The ID of the collection
    /// @param rateProvider The address of the rate provider
    /// @param tenor The tenor of the loan
    /// @return apr The APR
    function getBorrowOfferAPR(address user, uint256 collectionId, address rateProvider, uint256 tenor)
        external
        view
        returns (uint256);

    /// @notice Get the user copy loan offer for a given user
    /// @param user The address of the user
    /// @dev Added in v1.8.4
    /// @return copyLoanOfferConfig The user copy loan offer
    /// @return copyBorrowOfferConfig The user copy borrow offer
    function getUserDefinedCopyLimitOrderConfigs(address user)
        external
        view
        returns (CopyLimitOrderConfig memory copyLoanOfferConfig, CopyLimitOrderConfig memory copyBorrowOfferConfig);

    /// @notice Check if a user-defined loan offer is null
    /// @param user The address of the user
    /// @dev Added in v1.8.4
    /// @return isLoanOfferNull True if the user-defined loan offer is null, false otherwise
    /// @return isBorrowOfferNull True if the user-defined borrow offer is null, false otherwise
    function isUserDefinedLimitOrdersNull(address user)
        external
        view
        returns (bool isLoanOfferNull, bool isBorrowOfferNull);
}
