// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Size} from "@src/market/Size.sol";

import {BuyCreditLimitParams} from "@src/market/libraries/actions/BuyCreditLimit.sol";
import {InitializeRiskConfigParams} from "@src/market/libraries/actions/Initialize.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract BuyCreditLimitScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sizeContractAddress = vm.envAddress("SIZE_CONTRACT_ADDRESS");
        Size size = Size(payable(sizeContractAddress));

        console.log("Current Timestamp:", block.timestamp);

        InitializeRiskConfigParams memory riskConfig = size.riskConfig();
        if (riskConfig.maturities.length < 3) {
            revert("NOT_ENOUGH_MATURITIES");
        }
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = riskConfig.maturities[1];
        maturities[1] = riskConfig.maturities[2];

        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 0.1e18;
        aprs[1] = 0.2e18;

        BuyCreditLimitParams memory params = BuyCreditLimitParams({maturities: maturities, aprs: aprs});

        vm.startBroadcast(deployerPrivateKey);
        size.buyCreditLimit(params);
        vm.stopBroadcast();
    }
}
