// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {console2 as console} from "forge-std/Script.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {UniswapV3PriceFeed} from "@rheo-fm/src/oracle/adapters/UniswapV3PriceFeed.sol";
import {PriceFeedUniswapV3TWAPChainlink} from "@rheo-fm/src/oracle/v1.5.2/PriceFeedUniswapV3TWAPChainlink.sol";

contract GetPriceFeedUniswapV3TWAPChainlinkHistoricalDataScript is BaseScript, Networks, Deploy {
    function setUp() public {}

    function run() public broadcast {
        console.log("GetPriceFeedUniswapV3TWAPChainlinkHistoricalData...");

        uint256 toBlock = vm.getBlockNumber();
        uint256 fromBlock = 23921785;
        uint256 steps = 30;

        vm.rollFork(fromBlock);

        PriceFeedUniswapV3TWAPChainlink priceFeedUniswapV3TWAPChainlink =
            PriceFeedUniswapV3TWAPChainlink(0x19960f5ffa579a0573BF9b9D0D3258C34F9f69a1);
        UniswapV3PriceFeed uniswapV3PriceFeed = priceFeedUniswapV3TWAPChainlink.basePriceFeed();
        PriceFeed priceFeed = priceFeedUniswapV3TWAPChainlink.quotePriceFeed();

        console.log("timestamp,base,quote");
        for (uint256 b = fromBlock; b < toBlock; b += steps) {
            vm.rollFork(b);

            uint256 base = uniswapV3PriceFeed.getPrice();
            uint256 quote = priceFeed.getPrice();
            console.log("%s,%s,%s", block.timestamp, base, quote);
        }
    }
}
