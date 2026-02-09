// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract FrontendScript is Script {
    function run() external {
        console.log("Frontend...");

        Rheo size = Rheo(payable(vm.envAddress("SIZE_ADDRESS")));
        address user = vm.envAddress("USER_ADDRESS");
        bytes memory data = vm.envBytes("DATA");

        vm.prank(user);
        (bool success,) = address(size).call(data);
        console.log("success", success);
    }
}
