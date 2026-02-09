// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RheoView} from "@rheo-fm/src/market/RheoView.sol";

import {Logger} from "@rheo-fm/test/Logger.sol";

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract GetUserViewScript is Script, Logger {
    function run() external {
        console.log("GetUserView...");

        address rheoContractAddress = vm.envAddress("RHEO_CONTRACT_ADDRESS");
        address lender = vm.envAddress("LENDER");

        RheoView rheo = RheoView(rheoContractAddress);

        vm.startBroadcast();
        _log(rheo.getUserView(lender));
        vm.stopBroadcast();
    }
}
