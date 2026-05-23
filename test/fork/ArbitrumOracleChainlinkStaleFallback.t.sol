// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Networks} from "@rheo-fm/script/Networks.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {ChainlinkPriceFeed} from "@rheo-fm/src/oracle/adapters/ChainlinkPriceFeed.sol";
import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Test} from "forge-std/Test.sol";

/// @title ArbitrumOracleChainlinkStaleFallbackForkTest
/// @notice F2 — proves the v1.5.1 PriceFeed falls through to its UniswapV3 TWAP fallback when the
///         Chainlink primary path is stale.
///
///         Implementation note on why we *don't* use the production stale-price interval here:
///         the production PriceFeed sets `baseStalePriceInterval = 95040 s`. To force the production
///         feed into the stale branch on a fork, we'd need to either (a) `vm.warp` past 95 040 s
///         beyond the live `updatedAt` (which puts the test in a multi-day-forward state that
///         breaks Aave reserve math elsewhere if extended), or (b) successfully `vm.mockCall` the
///         Chainlink proxy, which proved unreliable on Arbitrum's `EACAggregatorProxy` pattern.
///         Cleaner: build a *separate* test-only PriceFeed using the same Arbitrum addresses but
///         with `stalePriceInterval = 1 s`. Live Chainlink updates lag block.timestamp by at least
///         a few seconds, so this PriceFeed treats every call as stale, deterministically driving
///         the wrapper into the try/catch fallback path. The actual wired-up production PriceFeed
///         is verified separately in `ArbitrumLiveMarketDeploymentForkTest::testFork_ArbitrumLive_
///         priceFeedSubContractsCorrectlyWired` (F11).
///
///         Run: `FOUNDRY_PROFILE=fork forge test --mc ArbitrumOracleChainlinkStaleFallbackForkTest -vvv`
contract ArbitrumOracleChainlinkStaleFallbackForkTest is Test, Networks {
    PriceFeed private priceFeed;

    function setUp() public {
        try vm.envString("API_KEY_ALCHEMY") returns (string memory) {
            vm.createSelectFork("arbitrum-production");
        } catch {
            vm.createSelectFork("arbitrum_archive");
        }

        // Mirror production wiring but with a 1-second stale interval to guarantee the Chainlink
        // path reverts STALE_PRICE on the first call.
        PriceFeedParams memory p = params("arbitrum-production-weth-usdc").priceFeedParams;
        p.baseStalePriceInterval = 1;
        p.quoteStalePriceInterval = 1;
        priceFeed = new PriceFeed(p);
    }

    /// @dev The Chainlink primary should be considered stale immediately (1-second interval) →
    ///      `chainlinkPriceFeed.getPrice()` reverts STALE_PRICE → PriceFeed wrapper falls through
    ///      to the UniswapV3 TWAP and returns a sane price.
    function testFork_ChainlinkStale_fallsThroughToUniswapAndReturnsSanePrice() public {
        // The live Arbitrum Chainlink ETH/USD feed updates roughly every minute, but can be as
        // fresh as `updatedAt == block.timestamp` at fork time. With a 1-second stale interval,
        // we need `block.timestamp - updatedAt > 1` — a 5-second warp guarantees this without
        // disturbing the Uniswap V3 pool's observation window.
        vm.warp(block.timestamp + 5);

        // Direct call to the Chainlink sub-feed should revert STALE_PRICE.
        // Cache the sub-contract reference first: `priceFeed.chainlinkPriceFeed()` is an
        // auto-generated getter — calling it inline ahead of `getPrice()` would consume the
        // `vm.expectRevert` token before we ever reach the call that should revert.
        ChainlinkPriceFeed clp = priceFeed.chainlinkPriceFeed();
        vm.expectRevert();
        clp.getPrice();

        // Wrapper succeeds via the Uniswap TWAP fallback.
        uint256 fallbackPrice = priceFeed.getPrice();
        assertGt(fallbackPrice, 1_000e18, "Uniswap fallback sane lower bound");
        assertLt(fallbackPrice, 100_000e18, "Uniswap fallback sane upper bound");
    }

    /// @dev Cross-check: production PriceFeed (95 040 s stale interval) does NOT fall through —
    ///      proves the fallback only fires when Chainlink is actually stale.
    function testFork_ProductionPriceFeed_doesNotFallThroughUnderNormalConditions() public {
        PriceFeed productionFeed = new PriceFeed(params("arbitrum-production-weth-usdc").priceFeedParams);
        // Should NOT revert — Chainlink primary returns live price.
        uint256 livePrice = productionFeed.chainlinkPriceFeed().getPrice();
        assertGt(livePrice, 0, "production feed Chainlink primary should return live price");

        uint256 wrapperPrice = productionFeed.getPrice();
        assertEq(wrapperPrice, livePrice, "wrapper should return Chainlink price under normal conditions");
    }
}
