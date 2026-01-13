// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";

import {USDC} from "@test/mocks/USDC.sol";
import {WETH} from "@test/mocks/WETH.sol";

import {BaseScript} from "@script/BaseScript.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {BaseTest} from "@test/BaseTest.sol";
import {SizeMock} from "@test/mocks/SizeMock.sol";

contract ForkTest is BaseTest, BaseScript {
    address public owner;
    IAToken public aToken;

    function setUp() public virtual override {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string memory rpcAlias = bytes(alchemyKey).length == 0 ? "base_archive" : "base";
        vm.createSelectFork(rpcAlias);
        ISize isize;
        (isize, priceFeed, owner) = importDeployments("base-production-weth-usdc");
        size = SizeMock(address(isize));
        usdc = USDC(address(size.data().underlyingBorrowToken));
        weth = WETH(payable(address(size.data().underlyingCollateralToken)));
        variablePool = size.data().variablePool;
        _labels();
        aToken = IAToken(variablePool.getReserveData(address(usdc)).aTokenAddress);
    }
}
