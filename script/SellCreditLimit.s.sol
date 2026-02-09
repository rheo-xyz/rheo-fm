// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";

import {InitializeRiskConfigParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {SellCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/SellCreditLimit.sol";
import {Logger} from "@rheo-fm/test/Logger.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract SellCreditLimitScript is Script, Logger {
    function run() external {
        console.log("SellCreditLimit...");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rheoContractAddress = vm.envAddress("RHEO_CONTRACT_ADDRESS");

        Rheo rheo = Rheo(payable(rheoContractAddress));

        InitializeRiskConfigParams memory riskConfig = rheo.riskConfig();
        if (riskConfig.maturities.length < 3) {
            revert("NOT_ENOUGH_MATURITIES");
        }
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = riskConfig.maturities[1];
        maturities[1] = riskConfig.maturities[2];

        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 0.1e18;
        aprs[1] = 0.2e18;

        SellCreditLimitParams memory params = SellCreditLimitParams({maturities: maturities, aprs: aprs});

        vm.startBroadcast(deployerPrivateKey);
        rheo.sellCreditLimit(params);
        vm.stopBroadcast();
    }
}
