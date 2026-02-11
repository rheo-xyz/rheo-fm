// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {IMultiSendCallOnly} from "@rheo-fm/script/interfaces/IMultiSendCallOnly.sol";

import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

contract ProposeSafeTxUpdateConfigScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    address signer;
    string derivationPath;
    ISizeFactory private sizeFactory;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        sizeFactory = ISizeFactory(vm.envAddress("RHEO_FACTORY"));

        _;
    }

    function run() public parseEnv broadcast {
        address[] memory marketAddresses = sizeFactory.getMarkets();

        string memory updateConfigKey = "swapFeeAPR";
        uint256 updateConfigValue = 0.005e18;

        address[] memory targets = new address[](marketAddresses.length);
        bytes[] memory datas = new bytes[](marketAddresses.length);

        // Rheo.updateConfig(key, value) for all markets
        for (uint256 i = 0; i < marketAddresses.length; i++) {
            targets[i] = marketAddresses[i];
            datas[i] = abi.encodeCall(
                Rheo.updateConfig, (UpdateConfigParams({key: updateConfigKey, value: updateConfigValue}))
            );
        }

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        Tenderly.VirtualTestnet[] memory vnets = tenderly.getVirtualTestnets();
        for (uint256 i = 0; i < vnets.length; i++) {
            tenderly.deleteVirtualTestnetById(vnets[i].id);
        }

        Tenderly.VirtualTestnet memory vnet = tenderly.createVirtualTestnet("update-config", block.chainid);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(
            vnet.id, signer, safe.instance().safe, safe.getExecTransactionsData(targets, datas, signer, derivationPath)
        );
    }
}
