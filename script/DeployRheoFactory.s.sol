// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {console2 as console} from "forge-std/Script.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

contract DeployRheoFactoryScript is BaseScript, Networks, Deploy {
    address deployer;
    address owner;
    string networkConfiguration;
    bool shouldUpgrade;

    function setUp() public {}

    modifier parseEnv() {
        deployer = vm.envOr("DEPLOYER_ADDRESS", vm.addr(vm.deriveKey(TEST_MNEMONIC, 0)));
        owner = vm.envOr("OWNER", address(0));
        networkConfiguration = vm.envOr("NETWORK_CONFIGURATION", TEST_NETWORK_CONFIGURATION);
        shouldUpgrade = vm.envOr("SHOULD_UPGRADE", false);
        _;
    }

    function run() public parseEnv broadcast {
        console.log("[RheoFactory v1.5] deploying...");

        console.log("[RheoFactory v1.5] networkConfiguration", networkConfiguration);
        console.log("[RheoFactory v1.5] deployer", deployer);
        console.log("[RheoFactory v1.5] owner", owner);

        RheoFactory implementation = new RheoFactory();

        console.log("[RheoFactory v1.5] implementation", address(implementation));

        if (shouldUpgrade) {
            ERC1967Proxy proxy =
                new ERC1967Proxy(address(implementation), abi.encodeCall(RheoFactory.initialize, (owner)));
            console.log("[RheoFactory v1.5] proxy", address(proxy));

            console.log("[RheoFactory v1.5] deployed\n");
        } else {
            console.log("[RheoFactory v1.5] upgrade pending, call `upgradeToAndCall`\n");
        }

        console.log("[RheoFactory v1.5] done");
    }
}
