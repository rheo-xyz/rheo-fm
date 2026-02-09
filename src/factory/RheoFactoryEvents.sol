// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title RheoFactoryEvents
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
abstract contract RheoFactoryEvents {
    event RheoImplementationSet(address indexed oldRheoImplementation, address indexed newRheoImplementation);
    event NonTransferrableRebasingTokenVaultImplementationSet(
        address indexed oldNonTransferrableRebasingTokenVaultImplementation,
        address indexed newNonTransferrableRebasingTokenVaultImplementation
    ); // v1.8
    event CollectionsManagerSet(address indexed oldCollectionsManager, address indexed newCollectionsManager); // v1.8

    event CreateMarket(address indexed market);
    event RemoveMarket(address indexed market);
    event CreatePriceFeed(address indexed priceFeed);
    event CreateBorrowTokenVault(address indexed borrowTokenVault); // v1.8

    event SetAuthorization(
        address indexed sender, address indexed operator, uint256 indexed actionsBitmap, uint256 nonce
    ); // v1.7
    event RevokeAllAuthorizations(address indexed sender); // v1.7
}
