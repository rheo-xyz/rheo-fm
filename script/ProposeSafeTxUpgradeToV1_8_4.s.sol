// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_8_4Script is BaseScript, Networks {
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
        console.log("ProposeSafeTxUpgradeToV1_8_4Script");

        vm.startBroadcast();

        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_8_4Data();

        vm.stopBroadcast();

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeToV1_8_4Script: done");
    }

    function getUpgradeToV1_8_4Data() public returns (address[] memory targets, bytes[] memory datas) {
        RheoFactory sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);

        IRheo[] memory unpausedMarkets = getUnpausedMarkets(sizeFactory);

        Rheo newRheoImplementation = new Rheo();
        console.log("ProposeSafeTxUpgradeToV1_8_4Script: newRheoImplementation", address(newRheoImplementation));

        targets = new address[](unpausedMarkets.length + 1);
        datas = new bytes[](unpausedMarkets.length + 1);
        for (uint256 i = 0; i < unpausedMarkets.length; i++) {
            targets[i] = address(unpausedMarkets[i]);
            datas[i] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newRheoImplementation), ""));
        }
        targets[unpausedMarkets.length] = address(sizeFactory);
        datas[unpausedMarkets.length] =
            abi.encodeCall(RheoFactory.setRheoImplementation, (address(newRheoImplementation)));
    }
}
