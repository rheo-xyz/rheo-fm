// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {ClaimParams} from "@rheo-fm/src/market/libraries/actions/Claim.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract ClaimScript is Script {
    function run() external {
        console.log("Claim...");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rheoContractAddress = vm.envAddress("RHEO_CONTRACT_ADDRESS");

        Rheo rheo = Rheo(payable(rheoContractAddress));

        ClaimParams memory params = ClaimParams({creditPositionId: 1});

        vm.startBroadcast(deployerPrivateKey);
        rheo.claim(params);
        vm.stopBroadcast();
    }
}
