// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

struct MarketInformation {
    bool initialized;
    EnumerableSet.AddressSet rateProviders;
}

struct UserCollectionCopyLimitOrderConfigs {
    CopyLimitOrderConfig copyLoanOfferConfig;
    CopyLimitOrderConfig copyBorrowOfferConfig;
}

/// @title CollectionManagerStorage
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @dev Introduced in v1.8
abstract contract CollectionsManagerBase {
    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    // size factory
    ISizeFactory sizeFactory;
    // collection Id counter
    uint256 collectionIdCounter;
    // mapping of collection Id to collection
    mapping(uint256 collectionId => mapping(IRheo market => MarketInformation marketInformation) collection) collections;
    // mapping of user to collection Ids set
    mapping(address user => EnumerableSet.UintSet collectionIds) userToCollectionIds;
    // mapping of user to collection Ids to CopyLimitOrderConfig
    mapping(
        address user
            => mapping(uint256 collectionId => UserCollectionCopyLimitOrderConfigs userCollectionCopyLimitOrderConfigs)
    ) userToCollectionCopyLimitOrderConfigs;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCollectionId(uint256 collectionId);
    error OnlyRheoFactory(address user);
    error MarketNotInCollection(uint256 collectionId, address market);

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyRheoFactoryHasRole(bytes32 role) {
        if (!AccessControlUpgradeable(address(sizeFactory)).hasRole(role, msg.sender)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    modifier onlyRheoFactory() {
        if (msg.sender != address(sizeFactory)) {
            revert OnlyRheoFactory(msg.sender);
        }
        _;
    }
}
