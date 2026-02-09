// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

import {CollectionsManagerBase} from "@rheo-fm/src/collections/CollectionsManagerBase.sol";
import {CollectionsManagerCuratorActions} from "@rheo-fm/src/collections/actions/CollectionsManagerCuratorActions.sol";
import {CollectionsManagerUserActions} from "@rheo-fm/src/collections/actions/CollectionsManagerUserActions.sol";
import {CollectionsManagerView} from "@rheo-fm/src/collections/actions/CollectionsManagerView.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";

import {DEFAULT_ADMIN_ROLE, IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

/// @title CollectionsManager
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice See the documentation in {ICollectionsManager}.
contract CollectionsManager is
    ICollectionsManager,
    CollectionsManagerBase,
    ERC721EnumerableUpgradeable,
    CollectionsManagerCuratorActions,
    CollectionsManagerView,
    CollectionsManagerUserActions,
    MulticallUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IRheoFactory _sizeFactory) external initializer {
        __ERC721_init("Rheo Collections", "SIZE_COLLECTIONS");
        __ERC721Enumerable_init();
        __Multicall_init();
        __UUPSUpgradeable_init();

        sizeFactory = _sizeFactory;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRheoFactoryHasRole(DEFAULT_ADMIN_ROLE)
    {}

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://api.rheo.xyz/collections/fm/";
    }
}
