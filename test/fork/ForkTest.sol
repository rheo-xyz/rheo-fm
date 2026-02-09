// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";

import {USDC} from "@rheo-fm/test/mocks/USDC.sol";
import {WETH} from "@rheo-fm/test/mocks/WETH.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {RheoMock} from "@rheo-fm/test/mocks/RheoMock.sol";

contract ForkTest is BaseTest, BaseScript {
    address public owner;
    IAToken public aToken;

    function setUp() public virtual override {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string memory rpcAlias = bytes(alchemyKey).length == 0 ? "base_archive" : "base";
        vm.createSelectFork(rpcAlias);
        IRheo isize;
        (isize, priceFeed, owner) = importDeployments("base-production-weth-usdc");
        size = RheoMock(address(isize));
        usdc = USDC(address(size.data().underlyingBorrowToken));
        weth = WETH(payable(address(size.data().underlyingCollateralToken)));
        variablePool = size.data().variablePool;
        _labels();
        aToken = IAToken(variablePool.getReserveData(address(usdc)).aTokenAddress);
    }
}
