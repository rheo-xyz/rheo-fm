// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";

import {NonTransferrableScaledTokenV1_2} from "@rheo-fm/deprecated/token/NonTransferrableScaledTokenV1_2.sol";
import {Networks} from "@rheo-fm/script/Networks.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {Vm} from "forge-std/Vm.sol";
import {console2 as console} from "forge-std/console2.sol";

contract GetV1_5ReinitializeDataWethUsdcAfterCbbtcUsdcScript is BaseScript, Networks {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    EnumerableMap.AddressToUintMap private addresses;
    IRheoFactory private sizeFactory;

    modifier parseEnv() {
        sizeFactory = IRheoFactory(vm.envAddress("RHEO_FACTORY"));
        _;
    }

    function run() external parseEnv ignoreGas {
        string memory marketName = "base-production-weth-usdc";
        uint256 deploymentBlock = uint256(17147278);
        IRheo market0 = sizeFactory.getMarket(0);
        address borrowTokenVault = address(market0.data().borrowTokenVault);

        console.log("GetV1_5ReinitializeDataWethUsdcAfterCbbtcUsdc...");

        (IRheo market,,) = importDeployments(marketName);

        // We use .data().borrowTokenVault here since, before the migration, it points to the V1_2 token.
        // After the migration, it will point to the V1_5 token
        NonTransferrableScaledTokenV1_2 borrowATokenV1_2 =
            NonTransferrableScaledTokenV1_2(address(market.data().borrowTokenVault));

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IERC20.Transfer.selector;

        uint256 toBlock = vm.getBlockNumber();
        uint256 fromBlock = deploymentBlock;
        uint256 batchRheo = 100_000;

        Vm.EthGetLogs[] memory logs;

        while (fromBlock < toBlock) {
            uint256 endBlock = (fromBlock + batchRheo > toBlock) ? toBlock : fromBlock + batchRheo;

            console.log("block range: %s - %s", fromBlock, endBlock);

            logs = vm.eth_getLogs(fromBlock, endBlock, address(borrowATokenV1_2), topics);

            for (uint256 j = 0; j < logs.length; j++) {
                Vm.EthGetLogs memory log = logs[j];
                address to = address(uint160(uint256(log.topics[2])));
                if (!addresses.contains(to)) {
                    uint256 balance = borrowATokenV1_2.balanceOf(to);
                    if (balance > 0) {
                        addresses.set(to, balance);
                    }
                }
            }

            fromBlock = endBlock + 1;
        }

        console.log("Market: %s, Users: %s", marketName, addresses.length());

        string memory networkConfiguration = string.concat(marketName, "-after-cbbtc-usdc");

        exportV1_5ReinitializeData(networkConfiguration, addresses, toBlock, borrowTokenVault);
    }
}
