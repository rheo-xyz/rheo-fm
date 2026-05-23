// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {Networks} from "@rheo-fm/script/Networks.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {Test} from "forge-std/Test.sol";

/// @title ArbitrumOracleSequencerDownForkTest
/// @notice F1 — exercises every revert branch in ChainlinkSequencerUptimeFeed.validateSequencerIsUp()
///         against the live Arbitrum sequencer-uptime feed. The v1.5.1 PriceFeed routes every
///         `getPrice()` call through this guard first; if it reverts, both Chainlink and Uniswap
///         paths are unreachable. These tests pin that behavior at the integration level.
///
///         Run: `FOUNDRY_PROFILE=fork forge test --mc ArbitrumOracleSequencerDownForkTest -vvv`
contract ArbitrumOracleSequencerDownForkTest is Test, Networks {
    AggregatorV3Interface private constant SEQUENCER_FEED =
        AggregatorV3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    PriceFeed private priceFeed;

    function setUp() public {
        try vm.envString("API_KEY_ALCHEMY") returns (string memory) {
            vm.createSelectFork("arbitrum-production");
        } catch {
            vm.createSelectFork("arbitrum_archive");
        }

        // Deploy a fresh PriceFeed using the canonical Arbitrum WETH/USDC params so the test
        // exercises the same wiring the production market will have.
        priceFeed = new PriceFeed(params("arbitrum-production-weth-usdc").priceFeedParams);
    }

    /// @dev `answer == 1` means sequencer is down per Chainlink spec.
    function testFork_SequencerDown_revertsWhenAnswerIsOne() public {
        _mockSequencerFeed({answer: 1, startedAt: block.timestamp - 1 days});
        vm.expectRevert(Errors.SEQUENCER_DOWN.selector);
        priceFeed.getPrice();
    }

    /// @dev `startedAt == 0` is an Arbitrum-specific "uninitialized round" state — also down.
    function testFork_SequencerDown_revertsWhenStartedAtIsZero() public {
        _mockSequencerFeed({answer: 0, startedAt: 0});
        vm.expectRevert(Errors.SEQUENCER_DOWN.selector);
        priceFeed.getPrice();
    }

    /// @dev Sequencer recovered, but within the 1-hour grace window — calls still blocked.
    function testFork_SequencerDown_revertsDuringGracePeriod() public {
        _mockSequencerFeed({answer: 0, startedAt: block.timestamp - 1800});
        vm.expectRevert(Errors.GRACE_PERIOD_NOT_OVER.selector);
        priceFeed.getPrice();
    }

    /// @dev Sequencer recovered, grace period expired — getPrice() succeeds again.
    function testFork_SequencerUp_succeedsPastGracePeriod() public {
        _mockSequencerFeed({answer: 0, startedAt: block.timestamp - 3601});
        // Should now route through to Chainlink (or its Uniswap fallback) and return a sane price.
        uint256 price = priceFeed.getPrice();
        assertGt(price, 1_000e18, "ETH/USDC sane lower bound");
        assertLt(price, 100_000e18, "ETH/USDC sane upper bound");
    }

    /// @dev Mock `latestRoundData()` on the live sequencer feed.
    ///      Signature: (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    function _mockSequencerFeed(int256 answer, uint256 startedAt) private {
        vm.mockCall(
            address(SEQUENCER_FEED),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), answer, startedAt, block.timestamp, uint80(1))
        );
    }
}
