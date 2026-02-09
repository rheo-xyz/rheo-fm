// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {PriceFeedChainlinkOnly4x} from "@rheo-fm/deprecated/oracle/v1.8/PriceFeedChainlinkOnly4x.sol";

import {MainnetAddresses} from "@rheo-fm/script/MainnetAddresses.s.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {Math} from "@rheo-fm/src/market/libraries/Math.sol";

import {InitializeOracleParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2Script} from
    "@rheo-fm/script/ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2.s.sol";
import {PriceFeedChainlinkMul} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkMul.sol";
import {PriceFeedChainlinkOnly4xV2} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkOnly4xV2.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";

import {console} from "forge-std/console.sol";

contract ForkPriceFeedChainlinkOnly4xBugReportTest is ForkTest, MainnetAddresses, Networks {
    uint256 private constant PRICE_SCALE = 1e18;
    // Prices derived from Chainlink feeds at mainnet block 24_343_753.
    uint256 private constant WBTC_USD_PRICE = 84_122_432_687_927_157_147_900;
    uint256 private constant ETH_USD_PRICE = 2_811_652_500_000_000_000_000;
    uint256 private constant USDC_USD_PRICE = 999_640_000_000_000_000;

    function setUp() public override(ForkTest) {
        vm.createSelectFork("mainnet", 24_343_753);

        sizeFactory = RheoFactory(Networks.contracts[block.chainid][Contract.RHEO_FACTORY]);
    }

    function testFork_PriceFeedChainlinkOnly4xBugReport_misprices_when_quote_is_non_pegged() public {
        // Configure to (WBTC/USD) / (ETH/USD) => WBTC/ETH, but implementation returns a product.
        PriceFeedChainlinkOnly4x wbtcToWeth = new PriceFeedChainlinkOnly4x(
            AggregatorV3Interface(CHAINLINK_WBTC_BTC.aggregator),
            AggregatorV3Interface(CHAINLINK_BTC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            CHAINLINK_WBTC_BTC.stalePriceInterval,
            CHAINLINK_BTC_USD.stalePriceInterval,
            CHAINLINK_ETH_USD.stalePriceInterval,
            CHAINLINK_ETH_USD.stalePriceInterval
        );

        uint256 buggy = wbtcToWeth.getPrice();
        uint256 expectedRatio = Math.mulDivDown(WBTC_USD_PRICE, PRICE_SCALE, ETH_USD_PRICE);

        console.log("WBTC/USD (1e18):", price(wbtcToWeth.baseToIntermediate1()));
        console.log("ETH/USD  (1e18):", price(wbtcToWeth.quoteToIntermediate2()));
        console.log("buggy price (WBTC/WETH?):", price(wbtcToWeth));
        console.log("expected ratio (WBTC/WETH):", format(expectedRatio, 18, 2));

        // Prove the mispricing is material and directionally wrong for non-pegged quotes.
        assertGt(buggy, expectedRatio * 1_000_000, "mispricing should be >1e6x for WBTC/WETH configuration");

        // Sanity: WBTC/ETH should be within a reasonable band at this block.
        // (Not asserting a precise price; just bounding to avoid false positives.)
        assertGt(expectedRatio, 1e18, "WBTC/ETH should be > 1");
        assertLt(expectedRatio, 1_000e18, "WBTC/ETH should be < 1000");

        PriceFeedChainlinkOnly4xV2 fixedFeed = new PriceFeedChainlinkOnly4xV2(
            AggregatorV3Interface(CHAINLINK_WBTC_BTC.aggregator),
            AggregatorV3Interface(CHAINLINK_BTC_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            AggregatorV3Interface(CHAINLINK_ETH_USD.aggregator),
            CHAINLINK_WBTC_BTC.stalePriceInterval,
            CHAINLINK_BTC_USD.stalePriceInterval,
            CHAINLINK_ETH_USD.stalePriceInterval,
            CHAINLINK_ETH_USD.stalePriceInterval
        );

        uint256 fixedPrice = fixedFeed.getPrice();
        assertApproxEqRel(fixedPrice, expectedRatio, 0.05e18, "V2 should return ratio up to 5%");
    }

    function testFork_PriceFeedChainlinkOnly4xBugReport_WBTC_USDC_priceFeed_is_product_but_V2_fixes() public {
        IRheo market = _findMarketBySymbols(sizeFactory, "WBTC", "USDC");
        InitializeOracleParams memory oracleParams = market.oracle();

        PriceFeedChainlinkOnly4x currentFeed = PriceFeedChainlinkOnly4x(oracleParams.priceFeed);

        uint256 currentPrice = currentFeed.getPrice();
        uint256 expectedRatio = Math.mulDivDown(WBTC_USD_PRICE, PRICE_SCALE, USDC_USD_PRICE);

        ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2Script proposeScript =
            new ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2Script();
        (address[] memory targets, bytes[] memory datas) = proposeScript.getUpdatePriceFeedsCalldata();
        _updatePriceFeeds(targets, datas);

        PriceFeedChainlinkOnly4xV2 fixedFeed = PriceFeedChainlinkOnly4xV2(market.oracle().priceFeed);
        uint256 fixedPrice = fixedFeed.getPrice();
        assertApproxEqRel(
            currentPrice,
            expectedRatio,
            0.01e18,
            "current price also match expected ratio up to a few percent since USDC/USD is close to 1"
        );
        assertApproxEqRel(fixedPrice, expectedRatio, 0.01e18, "V2 should return ratio up to a few percent");
        assertApproxEqRel(
            currentPrice, fixedPrice, 0.01e18, "current price should match fixed price up to a few percent"
        );

        console.log("WBTC/USDC current price (buggy)", price(currentFeed));
        console.log("WBTC/USDC fixed price", price(fixedFeed));
        console.log("WBTC/USDC expected ratio", format(expectedRatio, 18, 2));
    }

    function testFork_PriceFeedChainlinkOnly4xBugReport_upgraded_oracle_delta_is_small() public {
        ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2Script proposeScript =
            new ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2Script();
        (address[] memory targets, bytes[] memory datas) = proposeScript.getUpdatePriceFeedsCalldata();
        uint256[] memory oldPrices = new uint256[](targets.length);
        uint256[] memory newPrices = new uint256[](targets.length);

        for (uint256 i = 0; i < targets.length; i++) {
            IPriceFeed oldFeed = IPriceFeed(IRheo(targets[i]).oracle().priceFeed);
            oldPrices[i] = oldFeed.getPrice();
        }

        _updatePriceFeeds(targets, datas);

        for (uint256 i = 0; i < targets.length; i++) {
            IPriceFeed newFeed = IPriceFeed(IRheo(targets[i]).oracle().priceFeed);
            newPrices[i] = newFeed.getPrice();

            assertApproxEqRel(
                newPrices[i], oldPrices[i], 0.01e18, "price should be within a few percent of the old price"
            );
        }
    }

    function _updatePriceFeeds(address[] memory targets, bytes[] memory datas) internal {
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(contracts[block.chainid][Contract.RHEO_GOVERNANCE]);
            Address.functionCall(targets[i], datas[i]);
        }
    }

    function _findMarketBySymbols(RheoFactory sizeFactory, string memory collateralSymbol, string memory borrowSymbol)
        internal
        view
        returns (IRheo)
    {
        IRheo[] memory markets = sizeFactory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            IERC20Metadata collateralToken = markets[i].data().underlyingCollateralToken;
            IERC20Metadata borrowToken = markets[i].data().underlyingBorrowToken;
            if (
                Strings.equal(collateralToken.symbol(), collateralSymbol)
                    && Strings.equal(borrowToken.symbol(), borrowSymbol)
            ) {
                return markets[i];
            }
        }
        revert("Market not found");
    }
}
