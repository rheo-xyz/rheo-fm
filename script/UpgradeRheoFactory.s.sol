// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {console} from "forge-std/Script.sol";

contract UpgradeRheoFactoryScript is BaseScript, Deploy {
    address deployer;

    function setUp() public {}

    modifier parseEnv() {
        deployer = vm.envOr("DEPLOYER_ADDRESS", vm.addr(vm.deriveKey(TEST_MNEMONIC, 0)));
        _;
    }

    function run() public parseEnv broadcast {
        console.log("[RheoFactory v1.5] upgrading...");

        RheoFactory implementation = new RheoFactory();

        console.log("[RheoFactory v1.5] implementation", address(implementation));

        console.log("[RheoFactory v1.5] done");
    }
}
