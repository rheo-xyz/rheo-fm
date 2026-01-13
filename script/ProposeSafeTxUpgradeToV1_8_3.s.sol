// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {ICollectionsManager} from "@src/collections/interfaces/ICollectionsManager.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

import {Contract, Networks} from "@script/Networks.sol";

import {Size} from "@src/market/Size.sol";

import {IMulticall} from "@src/market/interfaces/IMulticall.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_8_3Script is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;
    SizeFactory private sizeFactory;
    ICollectionsManager private collectionsManager;

    uint256 private constant OVERDUE_LIQUIDATION_REWARD_PERCENT = 0.01e18;
    uint256 private constant OVERDUE_COLLATERAL_PROTOCOL_PERCENT = 0.001e18;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeToV1_8_3Script");

        vm.startBroadcast();

        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_8_3Data();

        vm.stopBroadcast();

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeToV1_8_3Script: done");
    }

    function getUpgradeToV1_8_3Data() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);

        ISize[] memory unpausedMarkets = getUnpausedMarkets(sizeFactory);

        Size newSizeImplementation = new Size();
        console.log("ProposeSafeTxUpgradeToV1_8_3Script: newSizeImplementation", address(newSizeImplementation));

        targets = new address[](unpausedMarkets.length + 1);
        datas = new bytes[](unpausedMarkets.length + 1);
        for (uint256 i = 0; i < unpausedMarkets.length; i++) {
            targets[i] = address(unpausedMarkets[i]);
            bytes[] memory multicallDatas = new bytes[](2);
            multicallDatas[0] = abi.encodeCall(
                ISizeAdmin.updateConfig,
                (
                    UpdateConfigParams({
                        key: "overdueCollateralProtocolPercent",
                        value: OVERDUE_COLLATERAL_PROTOCOL_PERCENT
                    })
                )
            );
            multicallDatas[1] = abi.encodeCall(
                ISizeAdmin.updateConfig,
                (
                    UpdateConfigParams({
                        key: "overdueLiquidationRewardPercent",
                        value: OVERDUE_LIQUIDATION_REWARD_PERCENT
                    })
                )
            );
            datas[i] = abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (address(newSizeImplementation), abi.encodeCall(IMulticall.multicall, (multicallDatas)))
            );
        }
        targets[unpausedMarkets.length] = address(sizeFactory);
        datas[unpausedMarkets.length] =
            abi.encodeCall(SizeFactory.setSizeImplementation, (address(newSizeImplementation)));
    }
}
