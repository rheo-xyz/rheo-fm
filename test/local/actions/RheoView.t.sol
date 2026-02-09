// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract RheoViewTest is BaseTest {
    function test_RheoView_getUserDefinedBorrowOfferAPR_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_OFFER.selector, alice));
        size.getUserDefinedBorrowOfferAPR(alice, block.timestamp);

        _sellCreditLimit(alice, block.timestamp + 150 days, FixedMaturityLimitOrderHelper.marketOffer());

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_MATURITY.selector));
        size.getUserDefinedBorrowOfferAPR(alice, 0);
    }

    function test_RheoView_getUserDefinedLoanOfferAPR_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_OFFER.selector, alice));
        size.getUserDefinedLoanOfferAPR(alice, block.timestamp);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_MATURITY.selector));
        size.getUserDefinedLoanOfferAPR(alice, 0);
    }

    function test_RheoView_getLoanStatus() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_POSITION_ID.selector, 0));
        size.getLoanStatus(0);
    }

    function test_RheoView_getSwapFee_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_MATURITY.selector));
        size.getSwapFee(100e6, 0);
    }

    function test_RheoView_isDebtPositionId_no_loans() public view {
        assertEq(size.isDebtPositionId(0), false);
    }
}
