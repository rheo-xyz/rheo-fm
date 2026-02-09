// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {Logger} from "@rheo-fm/test/Logger.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

contract BuyCreditMarketScript is Script, Logger {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rheoContractAddress = vm.envAddress("RHEO_CONTRACT_ADDRESS");
        Rheo rheo = Rheo(payable(rheoContractAddress));

        uint256 maturity = rheo.riskConfig().maturities[1];

        address lender = vm.envAddress("LENDER");
        address borrower = vm.envAddress("BORROWER");

        console.log("lender", lender);
        console.log("borrower", borrower);

        uint256 amount = 6e6;

        uint256 apr = rheo.getUserDefinedBorrowOfferAPR(borrower, maturity);

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: borrower,
            creditPositionId: RESERVED_ID,
            maturity: maturity,
            amount: amount,
            deadline: block.timestamp,
            minAPR: apr,
            exactAmountIn: false,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        console.log("lender USDC", rheo.getUserView(lender).borrowTokenBalance);
        vm.startBroadcast(deployerPrivateKey);
        rheo.buyCreditMarket(params);
        vm.stopBroadcast();
    }
}
