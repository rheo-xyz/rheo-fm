// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {LiquidateParams} from "@rheo-fm/src/market/libraries/actions/Liquidate.sol";
import {Logger} from "@rheo-fm/test/Logger.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract LiquidateScript is Script, Logger {
    function run() external {
        console.log("Liquidating...");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rheoContractAddress = vm.envAddress("RHEO_CONTRACT_ADDRESS");

        Rheo rheo = Rheo(payable(rheoContractAddress));

        LiquidateParams memory params =
            LiquidateParams({debtPositionId: 0, minimumCollateralProfit: 0, deadline: block.timestamp});

        vm.startBroadcast(deployerPrivateKey);
        rheo.liquidate(params);
        vm.stopBroadcast();
    }
}
