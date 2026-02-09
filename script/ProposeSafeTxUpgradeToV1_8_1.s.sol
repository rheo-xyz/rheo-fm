// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_8_1Script is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;
    RheoFactory private sizeFactory;
    ICollectionsManager private collectionsManager;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        _;
    }

    function run() public parseEnv broadcast {
        console.log("ProposeSafeTxUpgradeToV1_8_1Script");

        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_8_1Data();

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeToV1_8_1Script: done");
    }

    function getUpgradeToV1_8_1Data() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        collectionsManager = sizeFactory.collectionsManager();

        CollectionsManager newCollectionsManagerImplementation = new CollectionsManager();
        console.log(
            "ProposeSafeTxUpgradeToV1_8_1Script: newCollectionsManagerImplementation",
            address(newCollectionsManagerImplementation)
        );
        RheoFactory newRheoFactoryImplementation = new RheoFactory();
        console.log(
            "ProposeSafeTxUpgradeToV1_8_1Script: newRheoFactoryImplementation", address(newRheoFactoryImplementation)
        );

        targets = new address[](2);
        datas = new bytes[](2);

        // Upgrade RheoFactory
        targets[0] = address(sizeFactory);
        datas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newRheoFactoryImplementation), ""));

        // Upgrade CollectionsManager
        targets[1] = address(collectionsManager);
        datas[1] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newCollectionsManagerImplementation), ""));
    }
}
