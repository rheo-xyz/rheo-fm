// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";

import {console} from "forge-std/console.sol";

/// @dev Fix for https://github.com/rheo-xyz/rheo-solidity/issues/8
///      Upgrade the on-chain CollectionsManager proxy to the latest implementation that uses
///      `isUserDefinedLimitOrdersNull(address)` instead of the legacy per-offer null-check helpers.
contract ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.RHEO_GOVERNANCE]);
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script");

        vm.startBroadcast();
        (address[] memory targets, bytes[] memory datas) = getUpgradeCollectionsManagerV1_8_4_Update2Data();
        vm.stopBroadcast();

        for (uint256 i = 0; i < targets.length; i++) {
            console.log("targets[", i, "] :", targets[i]);
            console.logBytes(datas[i]);
        }

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script: done");
    }

    function getUpgradeCollectionsManagerV1_8_4_Update2Data()
        public
        returns (address[] memory targets, bytes[] memory datas)
    {
        RheoFactory sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        ICollectionsManager collectionsManager = sizeFactory.collectionsManager();

        CollectionsManager newCollectionsManagerImplementation = new CollectionsManager();
        console.log(
            "ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script: newCollectionsManagerImplementation",
            address(newCollectionsManagerImplementation)
        );

        targets = new address[](1);
        datas = new bytes[](1);

        targets[0] = address(collectionsManager);
        datas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newCollectionsManagerImplementation), ""));
    }
}
