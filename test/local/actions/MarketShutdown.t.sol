// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Errors} from "@src/market/libraries/Errors.sol";
import {LoanStatus, RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";

import {LiquidateParams} from "@src/market/libraries/actions/Liquidate.sol";
import {MarketShutdownParams} from "@src/market/libraries/actions/MarketShutdown.sol";
import {WithdrawParams} from "@src/market/libraries/actions/Withdraw.sol";

import {BaseTest} from "@test/BaseTest.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";

contract MarketShutdownTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _deploySizeMarket2();
    }

    function test_MarketShutdown_shutdown_with_active_loans() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _deposit(bob, weth, 200e18);
        _deposit(james, weth, 200e18);
        _deposit(candy, usdc, 200e6);

        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));
        _buyCreditLimit(candy, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.04e18));

        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, 365 days, false);
        uint256 creditPositionId1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1)[0];
        _sellCreditMarket(alice, candy, creditPositionId1, 40e6, 365 days);
        uint256[] memory creditPositionIdsDebt1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1);
        assertEq(creditPositionIdsDebt1.length, 2);

        uint256 debtPositionId2 = _sellCreditMarket(james, alice, RESERVED_ID, 80e6, 365 days, false);

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

        _buyCreditLimit(alice, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.03e18));

        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, 365 days, false);
        uint256 debtPositionId2 = _sellCreditMarket(james, alice, RESERVED_ID, 80e6, 365 days, false);

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
