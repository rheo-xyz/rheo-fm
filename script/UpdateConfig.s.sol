// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";
import {console2 as console} from "forge-std/console2.sol";

contract UpdateConfigScript is BaseScript {
    function run() external broadcast {
        console.log("UpdateConfig...");
        address rheoAddress = vm.envAddress("RHEO_ADDRESS");
        string memory key = "priceFeed";
        uint256 value = uint256(uint160(vm.envAddress("PRICE_FEED")));

        Rheo rheo = Rheo(payable(rheoAddress));

        rheo.updateConfig(UpdateConfigParams({key: key, value: value}));
    }
}
