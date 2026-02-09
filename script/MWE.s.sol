// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PendleSparkLinearDiscountOracle} from "@pendle/contracts/oracles/internal/PendleSparkLinearDiscountOracle.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {PriceFeedPendleSparkLinearDiscountChainlink} from
    "@rheo-fm/src/oracle/v1.7.1/PriceFeedPendleSparkLinearDiscountChainlink.sol";

import {HTTP} from "@safe-utils/../lib/solidity-http/src/HTTP.sol";

import {console} from "forge-std/console.sol";

contract MWEScript is BaseScript, Networks {
    using HTTP for *;

    HTTP.Client http;
    IRheoFactory sizeFactory;

    modifier parseEnv() {
        sizeFactory = IRheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        http.initialize();
        _;
    }

    function run() external parseEnv {
        IRheo market = sizeFactory.getMarket(1);
        IPriceFeed oldPriceFeed = IPriceFeed(market.oracle().priceFeed);
        uint256 oldPrice = oldPriceFeed.getPrice();
        console.log("old Price Feed", address(oldPriceFeed));

        console.log("oldPrice", oldPrice);

        (
            ,
            PendleSparkLinearDiscountOracle pendleOracle,
            AggregatorV3Interface underlyingChainlinkOracle,
            AggregatorV3Interface quoteChainlinkOracle,
            uint256 underlyingStalePriceInterval,
            uint256 quoteStalePriceInterval,
            ,
        ) = priceFeedPendleChainlink29May2025UsdcMainnet();

        PriceFeedPendleSparkLinearDiscountChainlink newPriceFeed = new PriceFeedPendleSparkLinearDiscountChainlink(
            pendleOracle,
            underlyingChainlinkOracle,
            quoteChainlinkOracle,
            underlyingStalePriceInterval,
            quoteStalePriceInterval
        );

        console.log("new Price Feed", address(newPriceFeed));

        string memory body = vm.serializeAddress(".", "priceFeed", address(newPriceFeed));

        HTTP.Response memory res = http.initialize("https://httpbin.org/post").POST().withBody(body).request();
        require(res.status == 200, "Failed to propose safe tx");
    }
}
