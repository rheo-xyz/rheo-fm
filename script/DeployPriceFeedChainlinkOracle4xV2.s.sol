// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/Script.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {Networks} from "@rheo-fm/script/Networks.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {MainnetAddresses} from "@rheo-fm/script/MainnetAddresses.s.sol";
import {PriceFeedChainlinkOnly4xV2} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkOnly4xV2.sol";

contract DeployPriceFeedChainlinkOracle4xV2Script is BaseScript, Networks, Deploy, MainnetAddresses {
    function setUp() public {}

    function run() public broadcast {
        console.log("[PriceFeedChainlinkOracle4xV2] deploying...");

        PriceFeedChainlinkOnly4xV2 wbtcToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_WBTC_BTC.aggregator),
            AggregatorV3Interface(CHAINLINK_BTC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_WBTC_BTC.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_BTC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (WBTC/USDC)", address(wbtcToUsdc), price(wbtcToUsdc));

        PriceFeedChainlinkOnly4xV2 cbbtcToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_cbBTC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_cbBTC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_cbBTC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_cbBTC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (cbBTC/USDC)", address(cbbtcToUsdc), price(cbbtcToUsdc));

        PriceFeedChainlinkOnly4xV2 wethToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_ETH_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_ETH_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (WETH/USDC)", address(wethToUsdc), price(wethToUsdc));

        PriceFeedChainlinkOnly4xV2 weethToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_weETH_ETH.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_weETH_ETH.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_ETH_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (weETH/USDC)", address(weethToUsdc), price(weethToUsdc));

        PriceFeedChainlinkOnly4xV2 cbethToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_cbETH_ETH.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_cbETH_ETH.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_ETH_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (cbETH/USDC)", address(cbethToUsdc), price(cbethToUsdc));

        PriceFeedChainlinkOnly4xV2 usrToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_USR_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USR_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_USR_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USR_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (USR/USDC)", address(usrToUsdc), price(usrToUsdc));

        PriceFeedChainlinkOnly4xV2 usdsToUsdc = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_USDS_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDS_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_USDC_USD.aggregator),
            1.1e18 * CHAINLINK_USDS_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDS_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18,
            1.1e18 * CHAINLINK_USDC_USD.stalePriceInterval / 1e18
        );
        console.log("PriceFeedChainlinkOnly4xV2 (USDS/USDC)", address(usdsToUsdc), price(usdsToUsdc));

        console.log("[PriceFeedChainlinkOracle4xV2] done");
    }
}
