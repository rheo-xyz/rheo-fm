// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {BaseTest, Vars} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";
import {Action, ActionsBitmap, Authorization} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

contract AuthorizationSetAuthorizationTest is BaseTest {
    function test_AuthorizationSetAuthorization_setAuthorization() public {
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        assertTrue(sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
        assertTrue(sizeFactory.isAuthorized(alice, alice, Action.SELL_CREDIT_MARKET));
        assertTrue(!sizeFactory.isAuthorized(candy, alice, Action.SELL_CREDIT_MARKET));

        assertTrue(!sizeFactory.isAuthorized(alice, bob, Action.SELL_CREDIT_MARKET));
        assertTrue(sizeFactory.isAuthorized(bob, bob, Action.SELL_CREDIT_MARKET));
        assertTrue(!sizeFactory.isAuthorized(candy, bob, Action.SELL_CREDIT_MARKET));

        assertTrue(!sizeFactory.isAuthorized(alice, candy, Action.SELL_CREDIT_MARKET));
        assertTrue(!sizeFactory.isAuthorized(bob, candy, Action.SELL_CREDIT_MARKET));
        assertTrue(sizeFactory.isAuthorized(candy, candy, Action.SELL_CREDIT_MARKET));
    }

    function test_AuthorizationSetAuthorization_set_unset() public {
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));
        assertTrue(sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
        _setAuthorization(alice, bob, Authorization.nullActionsBitmap());
        assertTrue(!sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
    }

    function test_AuthorizationSetAuthorization_setAuthorization_all() public {
        Action[] memory actions = new Action[](uint256(Action.NUMBER_OF_ACTIONS));
        for (uint256 i = 0; i < uint256(Action.NUMBER_OF_ACTIONS); i++) {
            actions[i] = Action(i);
        }
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(actions));
    }

    function test_AuthorizationSetAuthorization_setAuthorization_all_hardcoded() public {
        Action[] memory actions = new Action[](uint256(Action.NUMBER_OF_ACTIONS));
        actions[0] = Action.DEPOSIT;
        actions[1] = Action.WITHDRAW;
        actions[2] = Action.BUY_CREDIT_LIMIT;
        actions[3] = Action.SELL_CREDIT_LIMIT;
        actions[4] = Action.BUY_CREDIT_MARKET;
        actions[5] = Action.SELL_CREDIT_MARKET;
        actions[6] = Action.SELF_LIQUIDATE;
        actions[7] = Action.COMPENSATE;
        actions[8] = Action.SET_USER_CONFIGURATION;
        actions[9] = Action.SET_COPY_LIMIT_ORDER_CONFIGS;
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(actions));
    }

    function test_AuthorizationSetAuthorization_isValid() public pure {
        Action[] memory actions = new Action[](uint256(Action.NUMBER_OF_ACTIONS));
        for (uint256 i = 0; i < uint256(Action.NUMBER_OF_ACTIONS); i++) {
            actions[i] = Action(i);
        }
        ActionsBitmap actionsBitmap = Authorization.getActionsBitmap(actions);
        assertTrue(Authorization.isValid(actionsBitmap));

        uint256 invalidActionsBitmap = Authorization.toUint256(actionsBitmap) + 1;
        assertFalse(Authorization.isValid(ActionsBitmap.wrap(invalidActionsBitmap)));
    }

    function test_AuthorizationSetAuthorization_isActionSet() public pure {
        ActionsBitmap actionsBitmap = Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET);
        assertTrue(Authorization.isActionSet(actionsBitmap, Action.SELL_CREDIT_MARKET));
        assertFalse(Authorization.isActionSet(actionsBitmap, Action.BUY_CREDIT_MARKET));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_AuthorizationSetAuthorization_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        vm.prank(alice);
        sizeFactory.setAuthorization(address(0), Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_ACTIONS_BITMAP.selector, type(uint256).max));
        vm.prank(alice);
        sizeFactory.setAuthorization(bob, ActionsBitmap.wrap(type(uint256).max));

        Action lastAction = Action(uint256(Action.NUMBER_OF_ACTIONS) - 1);
        sizeFactory.setAuthorization(bob, ActionsBitmap.wrap(1 << uint256(lastAction)));

        uint256 invalidAction = uint256(Action.NUMBER_OF_ACTIONS);
        ActionsBitmap invalidActionsBitmap = ActionsBitmap.wrap(1 << invalidAction);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_ACTIONS_BITMAP.selector, invalidActionsBitmap));
        sizeFactory.setAuthorization(bob, invalidActionsBitmap);

        uint256 invalidActionPlusOne = uint256(Action.NUMBER_OF_ACTIONS) + 1;
        ActionsBitmap invalidActionPlusOneActionsBitmap = ActionsBitmap.wrap(1 << invalidActionPlusOne);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.INVALID_ACTIONS_BITMAP.selector, invalidActionPlusOneActionsBitmap)
        );
        vm.prank(alice);
        sizeFactory.setAuthorization(bob, invalidActionPlusOneActionsBitmap);
    }

    function test_AuthorizationSetAuthorization_isAuthorized() public {
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));

        assertTrue(sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
    }

    function test_AuthorizationSetAuthorization_revoke_single() public {
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET));
        assertTrue(sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
        _setAuthorization(alice, bob, ActionsBitmap.wrap(0));
        assertTrue(!sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
    }

    function test_AuthorizationSetAuthorization_multicall() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            sizeFactory.setAuthorization, (bob, Authorization.getActionsBitmap(Action.SELL_CREDIT_MARKET))
        );
        calls[1] = abi.encodeCall(
            sizeFactory.setAuthorization, (candy, Authorization.getActionsBitmap(Action.BUY_CREDIT_MARKET))
        );

        vm.prank(alice);
        MulticallUpgradeable(address(sizeFactory)).multicall(calls);

        assertTrue(sizeFactory.isAuthorized(bob, alice, Action.SELL_CREDIT_MARKET));
        assertTrue(!sizeFactory.isAuthorized(bob, alice, Action.BUY_CREDIT_MARKET));
        assertTrue(sizeFactory.isAuthorized(candy, alice, Action.BUY_CREDIT_MARKET));
        assertTrue(!sizeFactory.isAuthorized(candy, alice, Action.SELL_CREDIT_MARKET));
    }
}
