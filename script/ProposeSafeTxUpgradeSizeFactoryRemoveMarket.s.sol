// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {Contract, Networks} from "@script/Networks.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;
    SizeFactory private sizeFactory;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript");

        vm.startBroadcast();

        (address[] memory targets, bytes[] memory datas) = getUpgradeSizeFactoryData();

        vm.stopBroadcast();

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript: done");
    }

    function getUpgradeSizeFactoryData() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);

        SizeFactory newSizeFactoryImplementation = new SizeFactory();
        console.log(
            "ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript: newSizeFactoryImplementation",
            address(newSizeFactoryImplementation)
        );

        targets = new address[](1);
        datas = new bytes[](1);

        targets[0] = address(sizeFactory);
        datas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newSizeFactoryImplementation), ""));
    }
}

