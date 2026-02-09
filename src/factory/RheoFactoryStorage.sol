// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {ActionsBitmap} from "@rheo-fm/src/factory/libraries/Authorization.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

/// @title RheoFactoryStorage
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
// slither-disable-start uninitialized-state
// slither-disable-start constable-states
abstract contract RheoFactoryStorage {
    // the markets
    EnumerableSet.AddressSet markets;
    // the size implementation (used as implementation for proxy contracts, added in v1.6)
    address public sizeImplementation;
    // the non-transferrable token vault implementation (upgraded in v1.8)
    address public nonTransferrableTokenVaultImplementation;
    // mapping of authorized actions for operators per account (added in v1.7)
    mapping(
        uint256 nonce
            => mapping(address operator => mapping(address onBehalfOf => ActionsBitmap authorizedActionsBitmap))
    ) public authorizations;
    // mapping of authorization nonces per account (added in v1.7)
    mapping(address onBehalfOf => uint256 nonce) public authorizationNonces;
    // collections manager (added in v1.8)
    ICollectionsManager public collectionsManager;
}
// slither-disable-end constable-states
// slither-disable-end uninitialized-state
