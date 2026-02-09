// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {CompensateParams} from "@rheo-fm/src/market/libraries/actions/Compensate.sol";
import {Logger} from "@rheo-fm/test/Logger.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract CompensateScript is Script, Logger {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rheoContractAddress = vm.envAddress("RHEO_CONTRACT_ADDRESS");
        address lender = vm.envAddress("LENDER");
        address borrower = vm.envAddress("BORROWER");

        console.log("lender", lender);
        console.log("borrower", borrower);

        address currentAddress = vm.addr(deployerPrivateKey);
        Rheo rheo = Rheo(payable(rheoContractAddress));

        console.log(currentAddress);

        uint256 balance = rheo.getUserView(currentAddress).collateralTokenBalance;
        uint256 debt = rheo.getUserView(currentAddress).debtBalance;

        console.log("balance", balance);
        console.log("debt", debt);

        CompensateParams memory params =
            CompensateParams({creditPositionWithDebtToRepayId: 111, creditPositionToCompensateId: 123, amount: debt});

        vm.startBroadcast(deployerPrivateKey);
        rheo.compensate(params);
        vm.stopBroadcast();
    }
}
