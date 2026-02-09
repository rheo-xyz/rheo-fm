// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ICollectionsManagerCuratorActions} from
    "@rheo-fm/src/collections/interfaces/ICollectionsManagerCuratorActions.sol";
import {ICollectionsManagerUserActions} from "@rheo-fm/src/collections/interfaces/ICollectionsManagerUserActions.sol";
import {ICollectionsManagerView} from "@rheo-fm/src/collections/interfaces/ICollectionsManagerView.sol";

/// @title ICollectionsManager
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
interface ICollectionsManager is
    ICollectionsManagerCuratorActions,
    ICollectionsManagerUserActions,
    ICollectionsManagerView
{}
