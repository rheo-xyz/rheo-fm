// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/Script.sol";

import {IRheoV1_5} from "@rheo-fm/deprecated/interfaces/IRheoV1_5.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {Networks} from "@rheo-fm/script/Networks.sol";

contract ReinitializeScript is BaseScript, Networks, Deploy {
    address deployer;
    string networkConfiguration;
    address borrowTokenVault;
    address[] users;

    function setUp() public {}

    modifier parseEnv() {
        deployer = vm.envOr("DEPLOYER_ADDRESS", vm.addr(vm.deriveKey(TEST_MNEMONIC, 0)));
        networkConfiguration = vm.envOr("NETWORK_CONFIGURATION", TEST_NETWORK_CONFIGURATION);
        borrowTokenVault = vm.envAddress("BORROW_A_TOKEN_V1_5");
        users = vm.envAddress("USERS", ",");
        _;
    }

    function run() public parseEnv broadcast {
        console.log("[Rheo v1.5] reinitializing...\n");

        console.log("[Rheo v1.5] networkConfiguration", networkConfiguration);
        console.log("[Rheo v1.5] deployer", deployer);

        (IRheo proxy,,) = importDeployments(networkConfiguration);

        IRheoV1_5(address(proxy)).reinitialize(borrowTokenVault, users);

        console.log("[Rheo v1.5] done");
    }
}
