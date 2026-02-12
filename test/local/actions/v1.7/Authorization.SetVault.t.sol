// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";
import {UserView} from "@rheo-fm/src/market/RheoView.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {SetVaultOnBehalfOfParams, SetVaultParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";

import {Action, Authorization} from "@rheo-fm/src/factory/libraries/Authorization.sol";

import {ERC4626_ADAPTER_ID} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

contract AuthorizationSetVaultTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _setVaultAdapter(vaultSolady, ERC4626_ADAPTER_ID);
    }

    function test_AuthorizationSetVault_setVaultOnBehalfOf() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.SET_VAULT));

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(0));

        vm.prank(candy);
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(vaultSolady), forfeitOldShares: false}),
                onBehalfOf: alice
            })
        );

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(vaultSolady));
    }

    function test_AuthorizationSetVault_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.SET_VAULT));
        vm.prank(alice);
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(vaultSolady), forfeitOldShares: false}),
                onBehalfOf: bob
            })
        );
    }
}
