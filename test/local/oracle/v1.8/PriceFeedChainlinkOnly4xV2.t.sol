// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Math} from "@rheo-fm/src/market/libraries/Math.sol";
import {PriceFeedChainlinkMul} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkMul.sol";
import {PriceFeedChainlinkOnly4xV2} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkOnly4xV2.sol";

contract PriceFeedChainlinkOnly4xV2Test is Test {
    uint8 private constant DECIMALS = 8;
    uint256 private constant STALE_INTERVAL = 3600;
    int256 private constant BASE_PRICE = 5e8;
    int256 private constant INTERMEDIATE1_PRICE = 1000e8;
    int256 private constant QUOTE_PRICE = 2e8;
    int256 private constant INTERMEDIATE2_PRICE = 250e8;

    MockV3Aggregator private baseAggregator;
    MockV3Aggregator private intermediate1Aggregator;
    MockV3Aggregator private quoteAggregator;
    MockV3Aggregator private intermediate2Aggregator;
    PriceFeedChainlinkOnly4xV2 private priceFeed;

    function setUp() public {
        baseAggregator = new MockV3Aggregator(DECIMALS, BASE_PRICE);
        intermediate1Aggregator = new MockV3Aggregator(DECIMALS, INTERMEDIATE1_PRICE);
        quoteAggregator = new MockV3Aggregator(DECIMALS, QUOTE_PRICE);
        intermediate2Aggregator = new MockV3Aggregator(DECIMALS, INTERMEDIATE2_PRICE);

        priceFeed = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(address(baseAggregator)),
            AggregatorV3Interface(address(intermediate1Aggregator)),
            AggregatorV3Interface(address(quoteAggregator)),
            AggregatorV3Interface(address(intermediate2Aggregator)),
            STALE_INTERVAL,
            STALE_INTERVAL,
            STALE_INTERVAL,
            STALE_INTERVAL
        );
    }

    function test_PriceFeedChainlinkOnly4xV2_constructor_setsFeeds() public view {
        PriceFeedChainlinkMul baseToIntermediate1 = priceFeed.baseToIntermediate1();
        PriceFeedChainlinkMul quoteToIntermediate2 = priceFeed.quoteToIntermediate2();

        assertEq(address(baseToIntermediate1.baseAggregator()), address(baseAggregator));
        assertEq(address(baseToIntermediate1.quoteAggregator()), address(intermediate1Aggregator));
        assertEq(address(quoteToIntermediate2.baseAggregator()), address(quoteAggregator));
        assertEq(address(quoteToIntermediate2.quoteAggregator()), address(intermediate2Aggregator));
    }

    function test_PriceFeedChainlinkOnly4xV2_getPrice() public view {
        uint256 baseToIntermediate1Price = uint256(uint256(BASE_PRICE)) * uint256(uint256(INTERMEDIATE1_PRICE)) * 1e2;
        uint256 quoteToIntermediate2Price = uint256(uint256(QUOTE_PRICE)) * uint256(uint256(INTERMEDIATE2_PRICE)) * 1e2;
        uint256 expected = Math.mulDivDown(baseToIntermediate1Price, 1e18, quoteToIntermediate2Price);
        assertEq(priceFeed.getPrice(), expected);
    }

    function test_PriceFeedChainlinkOnly4xV2_constructor_null_address() public {
        vm.expectRevert(Errors.NULL_ADDRESS.selector);
        new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(address(0)),
            AggregatorV3Interface(address(intermediate1Aggregator)),
            AggregatorV3Interface(address(quoteAggregator)),
            AggregatorV3Interface(address(intermediate2Aggregator)),
            STALE_INTERVAL,
            STALE_INTERVAL,
            STALE_INTERVAL,
            STALE_INTERVAL
        );
    }

    function test_PriceFeedChainlinkOnly4xV2_constructor_null_stale_price() public {
        vm.expectRevert(Errors.NULL_STALE_PRICE.selector);
        new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(address(baseAggregator)),
            AggregatorV3Interface(address(intermediate1Aggregator)),
            AggregatorV3Interface(address(quoteAggregator)),
            AggregatorV3Interface(address(intermediate2Aggregator)),
            0,
            STALE_INTERVAL,
            STALE_INTERVAL,
            STALE_INTERVAL
        );
    }
}
