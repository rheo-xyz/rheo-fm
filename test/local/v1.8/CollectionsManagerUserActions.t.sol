// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CollectionsManagerBase} from "@rheo-fm/src/collections/CollectionsManagerBase.sol";

import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

contract CollectionsManagerUserActionsTest is BaseTest {
    function test_CollectionsManagerUserActions_subscribeToCollection_valid() public {
        uint256 collectionId = _createCollection(alice);

        _subscribeToCollection(bob, collectionId);

        assertEq(collectionsManager.isSubscribedToCollection(bob, collectionId), true);

        CopyLimitOrderConfig memory expectedConfig = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyLoanOfferConfig(bob, collectionId).minTenor,
            expectedConfig.minTenor
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyLoanOfferConfig(bob, collectionId).maxTenor,
            expectedConfig.maxTenor
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyLoanOfferConfig(bob, collectionId).minAPR,
            expectedConfig.minAPR
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyLoanOfferConfig(bob, collectionId).maxAPR,
            expectedConfig.maxAPR
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyLoanOfferConfig(bob, collectionId).offsetAPR,
            expectedConfig.offsetAPR
        );

        assertEq(
            collectionsManager.getUserDefinedCollectionCopyBorrowOfferConfig(bob, collectionId).minTenor,
            expectedConfig.minTenor
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyBorrowOfferConfig(bob, collectionId).maxTenor,
            expectedConfig.maxTenor
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyBorrowOfferConfig(bob, collectionId).minAPR,
            expectedConfig.minAPR
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyBorrowOfferConfig(bob, collectionId).maxAPR,
            expectedConfig.maxAPR
        );
        assertEq(
            collectionsManager.getUserDefinedCollectionCopyBorrowOfferConfig(bob, collectionId).offsetAPR,
            expectedConfig.offsetAPR
        );
    }

    function test_CollectionsManagerUserActions_subscribeToCollection_invalid() public {
        uint256 collectionId = _createCollection(alice);

        vm.expectRevert(abi.encodeWithSelector(CollectionsManagerBase.InvalidCollectionId.selector, collectionId + 1));
        _subscribeToCollection(bob, collectionId + 1);
    }

    function test_CollectionsManagerUserActions_unsubscribeFromCollection_valid() public {
        uint256 collectionId = _createCollection(alice);

        _subscribeToCollection(bob, collectionId);

        assertEq(collectionsManager.isSubscribedToCollection(bob, collectionId), true);

        _unsubscribeFromCollection(bob, collectionId);

        assertEq(collectionsManager.isSubscribedToCollection(bob, collectionId), false);
    }

    function test_CollectionsManagerUserActions_unsubscribeFromCollection_invalid() public {
        uint256 collectionId = _createCollection(alice);

        _subscribeToCollection(bob, collectionId);

        vm.expectRevert(abi.encodeWithSelector(CollectionsManagerBase.InvalidCollectionId.selector, collectionId + 1));
        _unsubscribeFromCollection(bob, collectionId + 1);
    }

    function test_CollectionsManagerUserActions_getSubscribedCollections() public {
        uint256 collectionId = _createCollection(alice);
        uint256 collectionId2 = _createCollection(bob);

        _subscribeToCollection(candy, collectionId);
        _subscribeToCollection(candy, collectionId2);

        uint256[] memory collectionIds = collectionsManager.getSubscribedCollections(candy);
        assertEq(collectionIds.length, 2);
        assertEq(collectionIds[0], collectionId);
        assertEq(collectionIds[1], collectionId2);
    }

    function test_CollectionsManagerUserActions_subscribeToCollection_only_through_RheoFactory() public {
        uint256 collectionId = _createCollection(alice);
        uint256[] memory collectionIds = new uint256[](1);
        collectionIds[0] = collectionId;

        vm.expectRevert(abi.encodeWithSelector(CollectionsManagerBase.OnlyRheoFactory.selector, bob));
        vm.prank(bob);
        collectionsManager.subscribeUserToCollections(bob, collectionIds);
    }
}
