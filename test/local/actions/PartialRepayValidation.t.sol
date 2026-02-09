// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {PartialRepayParams} from "@rheo-fm/src/market/libraries/actions/PartialRepay.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

contract PartialRepayValidationTest is BaseTest {
    function test_PartialRepay_validation() public {
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("fragmentationFee", 1e6);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 300e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(candy, weth, 100e18);
        _deposit(candy, usdc, 100e6);
        _buyCreditLimit(alice, block.timestamp + 30 days, _pointOfferAtIndex(0, 0));
        _buyCreditLimit(candy, block.timestamp + 30 days, _pointOfferAtIndex(0, 0));
        uint256 amount = 100e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, _maturity(30 days), false);

        uint256 creditId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        size.partialRepay(PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 0, borrower: bob}));

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_AMOUNT.selector, 100e6 + 1));
        size.partialRepay(
            PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 100e6 + 1, borrower: bob})
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_AMOUNT.selector, 100e6));
        size.partialRepay(PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 100e6, borrower: bob}));

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_BORROWER.selector, alice));
        size.partialRepay(
            PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 10e6, borrower: alice})
        );
        vm.stopPrank();

        _sellCreditMarket(alice, candy, creditId, 30e6, _maturity(30 days), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_AMOUNT.selector, 80e6));
        vm.prank(bob);
        size.partialRepay(PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 80e6, borrower: bob}));

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_AMOUNT.selector, 1e6));
        vm.prank(bob);
        size.partialRepay(PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 1e6, borrower: bob}));

        _repay(bob, debtPositionId, bob);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.LOAN_ALREADY_REPAID.selector, creditId));
        size.partialRepay(PartialRepayParams({creditPositionWithDebtToRepayId: creditId, amount: 10e6, borrower: bob}));
        vm.stopPrank();
    }
}
