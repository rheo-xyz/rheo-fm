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

import {PriceFeedChainlinkUniswapV3TWAPx2} from "@rheo-fm/src/oracle/v1.5.2/PriceFeedChainlinkUniswapV3TWAPx2.sol";

import {Networks} from "@rheo-fm/script/Networks.sol";

contract ForkPriceFeedChainlinkUniswapV3TWAPx2Test is ForkTest, Networks {
    PriceFeedChainlinkUniswapV3TWAPx2 public priceFeedsUSDeToUsdc;

    function setUp() public override(ForkTest) {
        super.setUp();
        vm.createSelectFork("mainnet");

        vm.rollFork(21579400);

        (
            PriceFeedParams memory chainlinkPriceFeedParams,
            PriceFeedParams memory uniswapV3BasePriceFeedParams,
            PriceFeedParams memory uniswapV3QuotePriceFeedParams
        ) = priceFeedsUSDeToUsdcMainnet();

        priceFeedsUSDeToUsdc = new PriceFeedChainlinkUniswapV3TWAPx2(
            chainlinkPriceFeedParams, uniswapV3BasePriceFeedParams, uniswapV3QuotePriceFeedParams
        );
    }

    function testFork_ForkPriceFeedChainlinkUniswapV3TWAPx2_getPrice_direct() public view {
        uint256 price = priceFeedsUSDeToUsdc.getPrice();
        assertEqApprox(price, 1.14e18, 0.01e18);
    }

    function testFork_ForkPriceFeedChainlinkUniswapV3TWAPx2_description() public view {
        assertEq(
            priceFeedsUSDeToUsdc.description(),
            "PriceFeedChainlinkUniswapV3TWAPx2 | ((sUSDe / USD) / (USDC / USD)) (Chainlink) | ((sUSDe / USDT) * (USDT / USDC)) (Uniswap v3 TWAP)"
        );
    }

    function testFork_ForkPriceFeedChainlinkUniswapV3TWAPx2_getPrice_fallback() public {
        vm.mockCallRevert(
            address(priceFeedsUSDeToUsdc.chainlinkPriceFeed()),
            abi.encodeWithSelector(IPriceFeed.getPrice.selector),
            "REVERT"
        );
        uint256 price = priceFeedsUSDeToUsdc.getPrice();
        assertEqApprox(price, 1.14e18, 0.01e18);
    }
}
