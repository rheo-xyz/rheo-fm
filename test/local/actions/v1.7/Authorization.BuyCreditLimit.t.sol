// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";
import {UserView} from "@src/market/SizeView.sol";
import {Errors} from "@src/market/libraries/Errors.sol";

import {Action, Authorization} from "@src/factory/libraries/Authorization.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@src/market/libraries/OfferLibrary.sol";
import {BuyCreditLimitOnBehalfOfParams, BuyCreditLimitParams} from "@src/market/libraries/actions/BuyCreditLimit.sol";

import {BaseTest} from "@test/BaseTest.sol";

contract AuthorizationBuyCreditLimitTest is BaseTest {
    using OfferLibrary for FixedMaturityLimitOrder;

    function test_AuthorizationBuyCreditLimit_buyCreditLimitOnBehalfOf() public {
        _setAuthorization(alice, bob, Authorization.getActionsBitmap(Action.BUY_CREDIT_LIMIT));

        _deposit(alice, weth, 100e18);
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 60 days;
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 1.01e18;
        aprs[1] = 1.02e18;
        assertTrue(_state().alice.user.loanOffer.isNull());

        vm.prank(bob);
        size.buyCreditLimitOnBehalfOf(
            BuyCreditLimitOnBehalfOfParams({
                params: BuyCreditLimitParams({maturities: maturities, aprs: aprs}),
                onBehalfOf: alice
            })
        );

        assertTrue(!_state().alice.user.loanOffer.isNull());
    }

    function test_AuthorizationBuyCreditLimit_validation() public {
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 60 days;
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 1.01e18;
        aprs[1] = 1.02e18;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.BUY_CREDIT_LIMIT)
        );
        vm.prank(alice);
        size.buyCreditLimitOnBehalfOf(
            BuyCreditLimitOnBehalfOfParams({
                params: BuyCreditLimitParams({maturities: maturities, aprs: aprs}),
                onBehalfOf: bob
            })
        );
    }
}
