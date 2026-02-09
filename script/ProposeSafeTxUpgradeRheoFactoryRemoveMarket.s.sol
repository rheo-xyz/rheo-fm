// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;
    RheoFactory private sizeFactory;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript");

        vm.startBroadcast();

        (address[] memory targets, bytes[] memory datas) = getUpgradeRheoFactoryData();

        vm.stopBroadcast();

        for (uint256 i = 0; i < targets.length; i++) {
            console.log("targets[", i, "] :", targets[i]);
            console.logBytes(datas[i]);
        }
        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript: done");
    }

    function getUpgradeRheoFactoryData() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);

        // Find all paused markets
        IRheo[] memory pausedMarkets = _getPausedMarkets();
        console.log("Found paused markets:", pausedMarkets.length);
        for (uint256 i = 0; i < pausedMarkets.length; i++) {
            console.log("  Paused market:", address(pausedMarkets[i]));
        }

        RheoFactory newRheoFactoryImplementation = new RheoFactory();
        console.log(
            "ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript: newRheoFactoryImplementation",
            address(newRheoFactoryImplementation)
        );

        // 1 upgrade + N removeMarket calls
        uint256 totalCalls = 1 + pausedMarkets.length;
        targets = new address[](totalCalls);
        datas = new bytes[](totalCalls);

        // First call: upgrade the factory
        targets[0] = address(sizeFactory);
        datas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newRheoFactoryImplementation), ""));

        // Subsequent calls: remove each paused market
        for (uint256 i = 0; i < pausedMarkets.length; i++) {
            targets[i + 1] = address(sizeFactory);
            datas[i + 1] = abi.encodeCall(RheoFactory.removeMarket, (address(pausedMarkets[i])));
        }
    }

    function _getPausedMarkets() internal view returns (IRheo[] memory pausedMarkets) {
        IRheo[] memory allMarkets = sizeFactory.getMarkets();
        pausedMarkets = new IRheo[](allMarkets.length);
        uint256 pausedCount = 0;

        for (uint256 i = 0; i < allMarkets.length; i++) {
            if (PausableUpgradeable(address(allMarkets[i])).paused()) {
                pausedMarkets[pausedCount] = allMarkets[i];
                pausedCount++;
            }
        }

        // Resize the array to actual count (using inherited function from Networks)
        _unsafeSetLength(pausedMarkets, pausedCount);
    }
}
