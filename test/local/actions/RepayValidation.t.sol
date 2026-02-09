// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {RepayParams} from "@rheo-fm/src/market/libraries/actions/Repay.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

contract RepayValidationTest is BaseTest {
    function test_Repay_validation() public {
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("fragmentationFee", 1e6);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 300e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(candy, weth, 100e18);
        _deposit(candy, usdc, 100e6);
        _buyCreditLimit(alice, block.timestamp + 30 days, _pointOfferAtIndex(0, 0.05e18));
        uint256 amount = 20e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, _maturity(30 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        address borrower = bob;
        _buyCreditLimit(candy, block.timestamp + 30 days, _pointOfferAtIndex(0, 0.03e18));

        uint256 creditId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
        _sellCreditMarket(alice, candy, creditId, 10e6, _maturity(30 days));

        vm.startPrank(bob);
        size.withdraw(WithdrawParams({token: address(usdc), amount: 100e6, to: bob}));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, amount, futureValue)
        );
        size.repay(RepayParams({debtPositionId: debtPositionId, borrower: borrower}));
        vm.stopPrank();

        _deposit(bob, usdc, 100e6);

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_BORROWER.selector, alice));
        size.repay(RepayParams({debtPositionId: debtPositionId, borrower: alice}));

        size.repay(RepayParams({debtPositionId: debtPositionId, borrower: borrower}));
        vm.expectRevert(abi.encodeWithSelector(Errors.LOAN_ALREADY_REPAID.selector, debtPositionId));
        size.repay(RepayParams({debtPositionId: debtPositionId, borrower: borrower}));
        vm.stopPrank();

        _claim(bob, creditId);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.LOAN_ALREADY_REPAID.selector, debtPositionId));
        size.repay(RepayParams({debtPositionId: debtPositionId, borrower: borrower}));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.LOAN_ALREADY_REPAID.selector, creditId));
        size.repay(RepayParams({debtPositionId: creditId, borrower: borrower}));
        vm.stopPrank();
    }
}
