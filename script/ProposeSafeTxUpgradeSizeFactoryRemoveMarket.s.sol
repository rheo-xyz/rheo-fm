// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

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

        for (uint256 i = 0; i < targets.length; i++) {
            console.log("targets[", i, "] :", targets[i]);
            console.logBytes(datas[i]);
        }
        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript: done");
    }

    function getUpgradeSizeFactoryData() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);

        // Find all paused markets
        ISize[] memory pausedMarkets = _getPausedMarkets();
        console.log("Found paused markets:", pausedMarkets.length);
        for (uint256 i = 0; i < pausedMarkets.length; i++) {
            console.log("  Paused market:", address(pausedMarkets[i]));
        }

        SizeFactory newSizeFactoryImplementation = new SizeFactory();
        console.log(
            "ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript: newSizeFactoryImplementation",
            address(newSizeFactoryImplementation)
        );

        // 1 upgrade + N removeMarket calls
        uint256 totalCalls = 1 + pausedMarkets.length;
        targets = new address[](totalCalls);
        datas = new bytes[](totalCalls);

        // First call: upgrade the factory
        targets[0] = address(sizeFactory);
        datas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newSizeFactoryImplementation), ""));

        // Subsequent calls: remove each paused market
        for (uint256 i = 0; i < pausedMarkets.length; i++) {
            targets[i + 1] = address(sizeFactory);
            datas[i + 1] = abi.encodeCall(SizeFactory.removeMarket, (address(pausedMarkets[i])));
        }
    }

    function _getPausedMarkets() internal view returns (ISize[] memory pausedMarkets) {
        ISize[] memory allMarkets = sizeFactory.getMarkets();
        pausedMarkets = new ISize[](allMarkets.length);
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
