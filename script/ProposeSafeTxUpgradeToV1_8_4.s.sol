// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {Contract, Networks} from "@script/Networks.sol";

import {Size} from "@src/market/Size.sol";

import {ISize} from "@src/market/interfaces/ISize.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_8_4Script is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
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
        SizeFactory sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);

        ISize[] memory unpausedMarkets = getUnpausedMarkets(sizeFactory);

        Size newSizeImplementation = new Size();
        console.log("ProposeSafeTxUpgradeToV1_8_4Script: newSizeImplementation", address(newSizeImplementation));

        targets = new address[](unpausedMarkets.length + 1);
        datas = new bytes[](unpausedMarkets.length + 1);
        for (uint256 i = 0; i < unpausedMarkets.length; i++) {
            targets[i] = address(unpausedMarkets[i]);
            datas[i] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newSizeImplementation), ""));
        }
        targets[unpausedMarkets.length] = address(sizeFactory);
        datas[unpausedMarkets.length] =
            abi.encodeCall(SizeFactory.setSizeImplementation, (address(newSizeImplementation)));
    }
}
