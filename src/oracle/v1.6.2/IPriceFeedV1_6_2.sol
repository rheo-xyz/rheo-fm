// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

/// @title IPriceFeedV1_6_2
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
interface IPriceFeedV1_6_2 is IPriceFeed {
    /// @notice Returns the description of the price feed
    function description() external view returns (string memory);
}
