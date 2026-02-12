// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/Script.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

contract UpgradeScript is BaseScript, Networks, Deploy {
    address deployer;
    string networkConfiguration;
    bool shouldUpgrade;

    function setUp() public {}

    modifier parseEnv() {
        deployer = vm.envOr("DEPLOYER_ADDRESS", vm.addr(vm.deriveKey(TEST_MNEMONIC, 0)));
        networkConfiguration = vm.envOr("NETWORK_CONFIGURATION", TEST_NETWORK_CONFIGURATION);
        shouldUpgrade = vm.envOr("SHOULD_UPGRADE", false);
        _;
    }

    function run() public parseEnv broadcast {
        console.log("[Rheo v1] upgrading...\n");

        console.log("[Rheo v1] networkConfiguration", networkConfiguration);
        console.log("[Rheo v1] deployer", deployer);

        Rheo upgrade = new Rheo();
        console.log("[Rheo v1] new implementation", address(upgrade));

        if (shouldUpgrade) {
            ISizeFactory factory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
            IRheo market = findMarketByNetworkConfiguration(address(factory), networkConfiguration);
            Rheo(address(market)).upgradeToAndCall(address(upgrade), "");
            console.log("[Rheo v1] upgraded\n");
        } else {
            console.log("[Rheo v1] upgrade pending, call `upgradeToAndCall`\n");
        }

        console.log("[Rheo v1] done");
    }
}
