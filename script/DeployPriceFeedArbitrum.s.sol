// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 3 — deploys the WETH/USDC PriceFeed using the params baked into
///         `Networks.sol::params("arbitrum-production-weth-usdc")`. EOA broadcast, no admin role.
///
/// @dev    The PriceFeed constructor internally deploys three sub-contracts:
///           - ChainlinkSequencerUptimeFeed  (Arbitrum L2 sequencer guard)
///           - ChainlinkPriceFeed             (primary: ETH/USD x USDC/USD aggregators)
///           - UniswapV3PriceFeed             (fallback: WETH/USDC 0.05% TWAP, 10 min window)
///         `forge --verify` will verify the top-level PriceFeed but NOT the sub-contracts. Use the
///         logged addresses + `forge verify-contract` to verify those three manually on Arbiscan.
///
///         Run:
///           forge script script/DeployPriceFeedArbitrum.s.sol \
///             --rpc-url arbitrum-production \
///             --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
///             --ffi --verify --broadcast -vvv
///
///         Heads up: the UniswapV3PriceFeed constructor calls
///         `pool.increaseObservationCardinalityNext(...)` if the pool's current cardinality is
///         below what's needed for the 10-minute TWAP. That's a one-time cost (~1M gas extra,
///         paid once for the pool) and is normal.
contract DeployPriceFeedArbitrumScript is BaseScript, Networks {
    function run() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);
        NetworkConfiguration memory cfg = params("arbitrum-production-weth-usdc");

        vm.startBroadcast();
        PriceFeed priceFeed = new PriceFeed(cfg.priceFeedParams);
        vm.stopBroadcast();

        // Sanity check: confirm the assembled feed returns a real price right away.
        uint256 price = priceFeed.getPrice();
        require(price > 0, "PriceFeed returned 0 at deploy time");

        console.log("[Phase 3] PriceFeed                    (new)", address(priceFeed));
        console.log("[Phase 3] ChainlinkSequencerUptimeFeed (sub)", address(priceFeed.chainlinkSequencerUptimeFeed()));
        console.log("[Phase 3] ChainlinkPriceFeed           (sub)", address(priceFeed.chainlinkPriceFeed()));
        console.log("[Phase 3] UniswapV3PriceFeed           (sub)", address(priceFeed.uniswapV3PriceFeed()));
        console.log("");
        console.log("Spot price (18 decimals):", price);
        console.log("");
        console.log("Verify sub-contracts on Arbiscan manually:");
        console.log(
            "  forge verify-contract <ChainlinkSequencerUptimeFeed-addr> ChainlinkSequencerUptimeFeed --chain 42161 --etherscan-api-key $API_KEY_ARBISCAN --watch"
        );
        console.log(
            "  forge verify-contract <ChainlinkPriceFeed-addr> ChainlinkPriceFeed --chain 42161 --etherscan-api-key $API_KEY_ARBISCAN --watch"
        );
        console.log(
            "  forge verify-contract <UniswapV3PriceFeed-addr> UniswapV3PriceFeed --chain 42161 --etherscan-api-key $API_KEY_ARBISCAN --watch"
        );
        console.log("");
        console.log("Next: export PRICE_FEED=", address(priceFeed));
    }
}
