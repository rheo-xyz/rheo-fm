// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/Script.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {PendleSparkLinearDiscountOracle} from "@pendle/contracts/oracles/internal/PendleSparkLinearDiscountOracle.sol";
import {IOracle} from "@rheo-fm/src/oracle/adapters/morpho/IOracle.sol";
import {PriceFeedPendleSparkLinearDiscountChainlink} from
    "@rheo-fm/src/oracle/v1.7.1/PriceFeedPendleSparkLinearDiscountChainlink.sol";

contract DeployPriceFeedPendleSparkLinearDiscountChainlinkScript is BaseScript, Networks, Deploy {
    function setUp() public {}

    function run() public broadcast {
        console.log("[PriceFeedPendleSparkLinearDiscountChainlink] deploying...");

        (
            PendleSparkLinearDiscountOracle pendleOracle,
            AggregatorV3Interface underlyingChainlinkOracle,
            AggregatorV3Interface quoteChainlinkOracle,
            uint256 underlyingStalePriceInterval,
            uint256 quoteStalePriceInterval,
            IERC20Metadata baseToken,
            IERC20Metadata quoteToken
        ) = priceFeedPendleSparkLinearDiscountChainlinkSusde24Sep2025UsdcMainnet();

        console.log("pendleOracle", address(pendleOracle));
        console.log("underlyingChainlinkOracle", underlyingChainlinkOracle.description());
        console.log("quoteChainlinkOracle", quoteChainlinkOracle.description());
        console.log("underlyingStalePriceInterval", underlyingStalePriceInterval);
        console.log("quoteStalePriceInterval", quoteStalePriceInterval);
        console.log("baseToken", baseToken.symbol());
        console.log("quoteToken", quoteToken.symbol());

        PriceFeedPendleSparkLinearDiscountChainlink priceFeedPendleChainlink = new PriceFeedPendleSparkLinearDiscountChainlink(
            pendleOracle,
            underlyingChainlinkOracle,
            quoteChainlinkOracle,
            underlyingStalePriceInterval,
            quoteStalePriceInterval
        );
        console.log("[PriceFeedPendleSparkLinearDiscountChainlink] priceFeed", address(priceFeedPendleChainlink));

        console.log("[PriceFeedPendleSparkLinearDiscountChainlink] done");
    }
}
