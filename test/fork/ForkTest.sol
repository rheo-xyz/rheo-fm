// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

contract ForkTest is BaseTest, BaseScript {
    address public owner;
    IAToken public aToken;

    function setUp() public virtual override {
        // Fork tests should configure forks/targets within their own `setUp` to avoid
        // coupling to any particular on-chain deployment or local file-based artifacts.
    }
}
