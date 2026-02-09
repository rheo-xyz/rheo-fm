// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

/// @title IRheoFactoryV1_8
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice The interface for the size factory v1.8
interface IRheoFactoryV1_8 {
    /// @notice Reinitialize the factory
    /// @param _collectionsManager The collections manager contract
    /// @param _users The users to reinitialize the factory for
    /// @param _curator The curator that will receive the collection
    /// @param _rateProvider The rate provider
    /// @param _collectionMarkets The markets for the collection
    /// @dev Before v1.8, users could copy rate providers directly through `copyLimitOrders`.
    ///        In v1.8, this method was deprecated in favor of collections and `setCopyLimitOrderConfigs`. The `reinitialize` function serves as a migration path
    ///        for users who are following the only off-chain collection currently offered by Rheo.
    ///      On mainnet, there are no off-chain collections. On Base, there is only one off-chain collection.
    ///      Although users could theoretically DoS/grief the reinitialization process by sybil copying the rate provider with multiple accounts,
    ///        these addresses are filtered on the backend by liquidity, so this is not a concern.
    /// @dev Deprecated in v1.8.1
    // function reinitialize(
    //     ICollectionsManager _collectionsManager,
    //     address[] memory _users,
    //     address _curator,
    //     address _rateProvider,
    //     IRheo[] memory _collectionMarkets
    // ) external;

    /// @notice Call a market with data. This can be used to batch operations on multiple markets.
    /// @param market The market to call
    /// @param data The data to call the market with
    /// @dev Anybody can do arbitrary Rheo calls with this function, so users MUST revoke authorizations at the end of the transaction.
    ///      Since this function executes arbitrary calls on Rheo markets, it should not have any trust assumptions on the ACL of factory-executed calls.
    function callMarket(IRheo market, bytes calldata data) external returns (bytes memory);

    /// @notice Subscribe to collections
    /// @param collectionIds The collection ids to subscribe to
    function subscribeToCollections(uint256[] memory collectionIds) external;

    /// @notice Unsubscribe from collections
    /// @param collectionIds The collection ids to unsubscribe from
    function unsubscribeFromCollections(uint256[] memory collectionIds) external;

    /// @notice Same as `subscribeToCollections` but `onBehalfOf`
    function subscribeToCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) external;

    /// @notice Same as `unsubscribeFromCollections` but `onBehalfOf`
    function unsubscribeFromCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) external;

    /// @notice Set the copy limit order configs for a user and collection
    /// @dev Added in v1.8.1
    function setUserCollectionCopyLimitOrderConfigs(
        uint256 collectionId,
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig
    ) external;

    /// @notice Same as `setUserCollectionCopyLimitOrderConfigs` but `onBehalfOf`
    /// @dev Added in v1.8.1
    function setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
        uint256 collectionId,
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig,
        address onBehalfOf
    ) external;

    /// @notice Get the loan offer APR
    /// @param user The user
    /// @param collectionId The collection id
    /// @param market The market
    /// @param rateProvider The rate provider
    /// @param maturity The maturity
    /// @return apr The APR
    /// @dev Since v1.8, this function is moved to the RheoFactory contract as it contains the link to the CollectionsManager, where collections provide APRs for different markets through rate providers
    function getLoanOfferAPR(address user, uint256 collectionId, IRheo market, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256);

    /// @notice Get the borrow offer APR
    /// @param user The user
    /// @param collectionId The collection id
    /// @param market The market
    /// @param rateProvider The rate provider
    /// @param maturity The maturity
    /// @return apr The APR
    /// @dev Since v1.8, this function is moved to the RheoFactory contract as it contains the link to the CollectionsManager, where collections provide APRs for different markets through rate providers
    function getBorrowOfferAPR(address user, uint256 collectionId, IRheo market, address rateProvider, uint256 maturity)
        external
        view
        returns (uint256);

    /// @notice Check if the borrow APR is lower than the loan offer APRs
    /// @param user The user
    /// @param borrowAPR The borrow APR
    /// @param market The market
    /// @param maturity The maturity
    /// @return isLower True if the borrow APR is lower than the loan offer APRs, false otherwise
    function isBorrowAPRLowerThanLoanOfferAPRs(address user, uint256 borrowAPR, IRheo market, uint256 maturity)
        external
        view
        returns (bool);

    /// @notice Check if the loan APR is greater than the borrow offer APRs
    /// @param user The user
    /// @param loanAPR The loan APR
    /// @param market The market
    /// @param maturity The maturity
    /// @return isGreater True if the loan APR is greater than the borrow offer APRs, false otherwise
    function isLoanAPRGreaterThanBorrowOfferAPRs(address user, uint256 loanAPR, IRheo market, uint256 maturity)
        external
        view
        returns (bool);
}
