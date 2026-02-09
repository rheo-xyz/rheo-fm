// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {console2 as console} from "forge-std/Script.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {Networks} from "@rheo-fm/script/Networks.sol";

contract UpgradeToAndCallV1_5Script is BaseScript, Networks, Deploy {
    string networkConfiguration;

    EnumerableMap.AddressToUintMap addresses;

    function setUp() public {}

    modifier parseEnv() {
        networkConfiguration = vm.envOr("NETWORK_CONFIGURATION", TEST_NETWORK_CONFIGURATION);
        _;
    }

    function run() public parseEnv broadcast {
        console.log("[Rheo v1] upgrading...\n");

        console.log("[Rheo v1] networkConfiguration", networkConfiguration);

        (IRheo proxy,,) = importDeployments(networkConfiguration);

        (, bytes memory data) = importV1_5ReinitializeData(networkConfiguration, addresses);

        Rheo upgrade = new Rheo();
        console.log("[Rheo v1] new implementation", address(upgrade));

        Rheo(address(proxy)).upgradeToAndCall(address(upgrade), data);
        console.log("[Rheo v1] upgraded\n");

        console.log("[Rheo v1] done");
    }
}
