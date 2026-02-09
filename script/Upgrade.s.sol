// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/Script.sol";

import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

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
            RheoFactory factory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
            IRheo market = _findMarketByNetworkConfiguration(factory, networkConfiguration);
            Rheo(address(market)).upgradeToAndCall(address(upgrade), "");
            console.log("[Rheo v1] upgraded\n");
        } else {
            console.log("[Rheo v1] upgrade pending, call `upgradeToAndCall`\n");
        }

        console.log("[Rheo v1] done");
    }

    function _findMarketByNetworkConfiguration(RheoFactory factory, string memory networkConfiguration)
        internal
        view
        returns (IRheo)
    {
        NetworkConfiguration memory cfg = params(networkConfiguration);
        IRheo[] memory markets = factory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            if (
                address(markets[i].data().underlyingCollateralToken) == cfg.underlyingCollateralToken
                    && address(markets[i].data().underlyingBorrowToken) == cfg.underlyingBorrowToken
            ) {
                return markets[i];
            }
        }
        revert InvalidNetworkConfiguration(networkConfiguration);
    }
}
