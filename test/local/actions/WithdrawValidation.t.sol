// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

contract WithdrawValidationTest is BaseTest {
    function test_Withdraw_validation() public {
        _deposit(alice, usdc, 1e6);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TOKEN.selector, address(0)));
        size.withdraw(WithdrawParams({token: address(0), amount: 1, to: alice}));

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        size.withdraw(WithdrawParams({token: address(weth), amount: 0, to: alice}));

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        size.withdraw(WithdrawParams({token: address(weth), amount: 1e6, to: address(0)}));
    }
}
