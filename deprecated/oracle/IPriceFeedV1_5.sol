// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

/// @title IPriceFeedV1_5
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Getters from previous PriceFeed implementation. Maintained for backwards compatibility.
interface IPriceFeedV1_5 is IPriceFeed {
    function base() external view returns (AggregatorV3Interface);
    function quote() external view returns (AggregatorV3Interface);
    function baseStalePriceInterval() external view returns (uint256);
    function quoteStalePriceInterval() external view returns (uint256);
}
