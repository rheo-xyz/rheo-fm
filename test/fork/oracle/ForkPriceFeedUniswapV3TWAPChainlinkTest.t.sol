// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PriceFeedV1_5} from "@rheo-fm/deprecated/oracle/PriceFeedV1_5.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {PriceFeedUniswapV3TWAPChainlink} from "@rheo-fm/src/oracle/v1.5.2/PriceFeedUniswapV3TWAPChainlink.sol";

import {PriceFeedUniswapV3TWAPChainlinkTest} from "@rheo-fm/test/local/oracle/PriceFeedUniswapV3TWAPChainlink.t.sol";

import {Networks} from "@rheo-fm/script/Networks.sol";

contract ForkPriceFeedUniswapV3TWAPChainlinkTest is ForkTest, Networks {
    PriceFeedUniswapV3TWAPChainlink public priceFeedVirtualToUsdc;

    function setUp() public override(ForkTest) {
        super.setUp();
        vm.createSelectFork("base_archive");

        // 2024-12-19 16h20 UTC
        vm.rollFork(23917935);

        (AggregatorV3Interface sequencerUptimeFeed, PriceFeedParams memory base, PriceFeedParams memory quote) =
            priceFeedVirtualUsdcBaseMainnet();

        priceFeedVirtualToUsdc = new PriceFeedUniswapV3TWAPChainlink(sequencerUptimeFeed, base, quote);
    }

    function testFork_ForkPriceFeedUniswapV3TWAPChainlink_getPrice() public view {
        uint256 price = priceFeedVirtualToUsdc.getPrice();
        assertEqApprox(price, 2.359e18, 0.001e18);
    }

    function testFork_ForkPriceFeedUniswapV3TWAPChainlink_description() public view {
        assertEq(
            priceFeedVirtualToUsdc.description(),
            "PriceFeedUniswapV3TWAPChainlink | (VIRTUAL/WETH) (Uniswap v3 TWAP) * ((ETH / USD) / (USDC / USD)) (PriceFeed)"
        );
    }
}
