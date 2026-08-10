// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {LoanStatus, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {LiquidateParams} from "@rheo-fm/src/market/libraries/actions/Liquidate.sol";
import {MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

contract MarketShutdownTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _deployRheoMarket2();
    }

    function test_MarketShutdown_shutdown_with_active_loans() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _deposit(bob, weth, 200e18);
        _deposit(james, weth, 200e18);
        _deposit(candy, usdc, 200e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.04e18));

        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 creditPositionId1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1)[0];
        _sellCreditMarket(alice, candy, creditPositionId1, 40e6, _maturity(150 days));
        uint256[] memory creditPositionIdsDebt1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1);
        assertEq(creditPositionIdsDebt1.length, 2);

        uint256 debtPositionId2 = _sellCreditMarket(james, alice, RESERVED_ID, 80e6, _maturity(150 days), false);

        uint256 adminWethBefore = weth.balanceOf(address(this));
        uint256 bobWethBefore = weth.balanceOf(bob);
        uint256 jamesWethBefore = weth.balanceOf(james);

        uint256 bobCollateralBefore = size.data().collateralToken.balanceOf(bob);
        uint256 jamesCollateralBefore = size.data().collateralToken.balanceOf(james);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LOAN_NOT_LIQUIDATABLE.selector,
                debtPositionId1,
                size.collateralRatio(bob),
                uint8(LoanStatus.ACTIVE)
            )
        );
        size.liquidate(
            LiquidateParams({debtPositionId: debtPositionId1, minimumCollateralProfit: 0, deadline: block.timestamp})
        );

        uint256 creditPositionId2 = size.getCreditPositionIdsByDebtPositionId(debtPositionId2)[0];

        uint256 totalFutureValue =
            size.getDebtPosition(debtPositionId1).futureValue + size.getDebtPosition(debtPositionId2).futureValue;
        _deposit(address(this), usdc, totalFutureValue);

        uint256 debtInCollateral1 =
            size.debtTokenAmountToCollateralTokenAmount(size.getDebtPosition(debtPositionId1).futureValue);
        uint256 debtInCollateral2 =
            size.debtTokenAmountToCollateralTokenAmount(size.getDebtPosition(debtPositionId2).futureValue);

        uint256[] memory debtPositionIds = new uint256[](2);
        debtPositionIds[0] = debtPositionId1;
        debtPositionIds[1] = debtPositionId2;

        uint256[] memory creditPositionIds = new uint256[](3);
        creditPositionIds[0] = creditPositionIdsDebt1[0];
        creditPositionIds[1] = creditPositionIdsDebt1[1];
        creditPositionIds[2] = creditPositionId2;

        address[] memory usersToForceWithdraw = new address[](3);
        usersToForceWithdraw[0] = bob;
        usersToForceWithdraw[1] = james;
        usersToForceWithdraw[2] = address(this);

        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: debtPositionIds,
                creditPositionIdsToClaim: creditPositionIds,
                usersToForceWithdraw: usersToForceWithdraw,
                shouldCheckSupply: true
            })
        );

        assertFalse(size.paused());
        assertEq(size.data().debtToken.totalSupply(), 0);
        assertEq(size.data().collateralToken.totalSupply(), 0);
        assertEq(weth.balanceOf(address(this)) - adminWethBefore, debtInCollateral1 + debtInCollateral2);
        assertEq(weth.balanceOf(bob) - bobWethBefore, bobCollateralBefore - debtInCollateral1);
        assertEq(weth.balanceOf(james) - jamesWethBefore, jamesCollateralBefore - debtInCollateral2);
    }

    function test_MarketShutdown_shutdown_can_be_split_across_multiple_txs() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _deposit(bob, weth, 200e18);
        _deposit(james, weth, 200e18);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));

        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 debtPositionId2 = _sellCreditMarket(james, alice, RESERVED_ID, 80e6, _maturity(150 days), false);

        uint256[] memory creditPositionIds1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1);
        uint256[] memory creditPositionIds2 = size.getCreditPositionIdsByDebtPositionId(debtPositionId2);

        uint256 totalFutureValue =
            size.getDebtPosition(debtPositionId1).futureValue + size.getDebtPosition(debtPositionId2).futureValue;
        _deposit(address(this), usdc, totalFutureValue);

        uint256[] memory debtPositionIdsBatch1 = new uint256[](1);
        debtPositionIdsBatch1[0] = debtPositionId1;
        address[] memory usersToForceWithdrawBatch1 = new address[](1);
        usersToForceWithdrawBatch1[0] = bob;

        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: debtPositionIdsBatch1,
                creditPositionIdsToClaim: creditPositionIds1,
                usersToForceWithdraw: usersToForceWithdrawBatch1,
                shouldCheckSupply: false
            })
        );

        assertFalse(size.paused());
        assertGt(size.data().debtToken.totalSupply(), 0);
        assertGt(size.data().collateralToken.totalSupply(), 0);

        uint256[] memory debtPositionIdsBatch2 = new uint256[](1);
        debtPositionIdsBatch2[0] = debtPositionId2;
        address[] memory usersToForceWithdrawBatch2 = new address[](2);
        usersToForceWithdrawBatch2[0] = james;
        usersToForceWithdrawBatch2[1] = address(this);

        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: debtPositionIdsBatch2,
                creditPositionIdsToClaim: creditPositionIds2,
                usersToForceWithdraw: usersToForceWithdrawBatch2,
                shouldCheckSupply: true
            })
        );

        assertFalse(size.paused());
        assertEq(size.data().debtToken.totalSupply(), 0);
        assertEq(size.data().collateralToken.totalSupply(), 0);
    }

    function test_MarketShutdown_shutdown_with_only_deposits() public {
        _deposit(alice, usdc, 250e6);
        _deposit(bob, weth, 50e18);

        uint256 adminWethBefore = weth.balanceOf(address(this));
        uint256 bobWethBefore = weth.balanceOf(bob);
        uint256 bobCollateralBefore = size.data().collateralToken.balanceOf(bob);

        address[] memory usersToForceWithdraw = new address[](1);
        usersToForceWithdraw[0] = bob;

        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: new uint256[](0),
                creditPositionIdsToClaim: new uint256[](0),
                usersToForceWithdraw: usersToForceWithdraw,
                shouldCheckSupply: true
            })
        );

        assertFalse(size.paused());
        assertEq(size.data().debtToken.totalSupply(), 0);
        assertEq(size.data().collateralToken.totalSupply(), 0);
        assertEq(weth.balanceOf(address(this)), adminWethBefore);
        assertEq(weth.balanceOf(bob) - bobWethBefore, bobCollateralBefore);
    }

    function test_MarketShutdown_only_admin_can_shutdown() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, 0x00));
        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: new uint256[](0),
                creditPositionIdsToClaim: new uint256[](0),
                usersToForceWithdraw: new address[](0),
                shouldCheckSupply: true
            })
        );
    }

    function test_MarketShutdown_claims_repaid_but_unclaimed_credit_positions() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _deposit(bob, weth, 200e18);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        _deposit(bob, usdc, futureValue);
        _repay(bob, debtPositionId, bob);

        // the loan is repaid, but the lender has not claimed yet, so the repayment assets belong to the market
        assertEq(size.data().debtToken.totalSupply(), 0);
        assertEq(size.getCreditPosition(creditPositionId).credit, futureValue);
        assertGe(size.data().borrowTokenVault.balanceOf(address(size)), futureValue);

        uint256 aliceBalanceBefore = size.data().borrowTokenVault.balanceOf(alice);

        address[] memory usersToForceWithdraw = new address[](1);
        usersToForceWithdraw[0] = bob;

        // the credit position is not passed in the params, it must be claimed by the shutdown itself
        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: new uint256[](0),
                creditPositionIdsToClaim: new uint256[](0),
                usersToForceWithdraw: usersToForceWithdraw,
                shouldCheckSupply: true
            })
        );

        assertEq(size.getCreditPosition(creditPositionId).credit, 0);
        assertEq(size.data().borrowTokenVault.balanceOf(address(size)), 0);
        assertGe(size.data().borrowTokenVault.balanceOf(alice) - aliceBalanceBefore, futureValue);

        // the claimed assets are the lender's own, so they survive the removal of the market
        sizeFactory.removeMarket(address(size1));

        uint256 usdcBalanceBefore = usdc.balanceOf(alice);
        size = size2;
        _withdraw(alice, usdc, type(uint256).max);
        assertGe(usdc.balanceOf(alice) - usdcBalanceBefore, futureValue);
    }

    function test_MarketShutdown_reverts_if_credit_positions_cannot_be_settled() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _deposit(bob, weth, 200e18);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        // the active loan is not force liquidated, so its credit cannot be claimed
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_AMOUNT.selector, futureValue));
        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: new uint256[](0),
                creditPositionIdsToClaim: new uint256[](0),
                usersToForceWithdraw: new address[](0),
                shouldCheckSupply: true
            })
        );
    }

    function test_MarketShutdown_can_withdraw_borrow_tokens_via_other_market() public {
        uint256 usdcAmount = 200e6;

        size = size1;
        _deposit(bob, usdc, usdcAmount);

        size.marketShutdown(
            MarketShutdownParams({
                debtPositionIdsToForceLiquidate: new uint256[](0),
                creditPositionIdsToClaim: new uint256[](0),
                usersToForceWithdraw: new address[](0),
                shouldCheckSupply: true
            })
        );

        size.pause();
        assertTrue(size1.paused());

        vm.startPrank(bob);
        vm.expectRevert(abi.encodePacked(Pausable.EnforcedPause.selector));
        size1.withdraw(WithdrawParams({token: address(usdc), amount: usdcAmount, to: bob}));
        vm.stopPrank();

        uint256 usdcBalanceBefore = usdc.balanceOf(bob);

        size = size2;
        _withdraw(bob, usdc, type(uint256).max);

        assertEq(size2.data().borrowTokenVault.balanceOf(bob), 0);
        assertGt(usdc.balanceOf(bob), usdcBalanceBefore);
    }
}
