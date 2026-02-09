// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Math} from "@rheo-fm/src/market/libraries/Math.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

import {ChainlinkSequencerUptimeFeed} from "@rheo-fm/src/oracle/adapters/ChainlinkSequencerUptimeFeed.sol";
import {UniswapV3PriceFeed} from "@rheo-fm/src/oracle/adapters/UniswapV3PriceFeed.sol";
import {PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";
import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";
import {IPriceFeedV1_5_3} from "@rheo-fm/src/oracle/v1.5.3/IPriceFeedV1_5_3.sol";

/// @title PriceFeedUniswapV3TWAP
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice A contract that provides the price of a `base` asset in terms of a `quote` asset, scaled to 18 decimals,
///           using Uniswap V3 for the `base` to `quote` pair
/// @dev `decimals` must be 18 to comply with Rheo contracts
///      `sequencerUptimeFeed` can be null for unsupported networks
///      In case the sequencer is down, `getPrice` reverts (see `ChainlinkSequencerUptimeFeed`)
///      This oracle should only be used for assets that are not supported by Chainlink
contract PriceFeedUniswapV3TWAP is IPriceFeedV1_5_3 {
    /* solhint-disable */
    uint256 public constant decimals = 18;
    ChainlinkSequencerUptimeFeed public immutable chainlinkSequencerUptimeFeed;
    UniswapV3PriceFeed public immutable baseToQuotePriceFeed;
    /* solhint-enable */

    constructor(AggregatorV3Interface sequencerUptimeFeed, PriceFeedParams memory baseToQuotePriceFeedParams) {
        chainlinkSequencerUptimeFeed = new ChainlinkSequencerUptimeFeed(sequencerUptimeFeed);
        baseToQuotePriceFeed = new UniswapV3PriceFeed(
            decimals,
            // other parameters of baseToQuotePriceFeedParams are unused
            baseToQuotePriceFeedParams.baseToken,
            baseToQuotePriceFeedParams.quoteToken,
            baseToQuotePriceFeedParams.uniswapV3Pool,
            baseToQuotePriceFeedParams.twapWindow,
            baseToQuotePriceFeedParams.averageBlockTime
        );
    }

    function getPrice() external view override returns (uint256) {
        chainlinkSequencerUptimeFeed.validateSequencerIsUp();
        return baseToQuotePriceFeed.getPrice();
    }

    function description() external view override returns (string memory) {
        return string.concat(
            "PriceFeedUniswapV3TWAP | (",
            baseToQuotePriceFeed.baseToken().symbol(),
            "/",
            baseToQuotePriceFeed.quoteToken().symbol(),
            ") (Uniswap v3 TWAP)"
        );
    }
}
