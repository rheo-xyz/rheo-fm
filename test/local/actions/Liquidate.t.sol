// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {LiquidateParams} from "@src/market/libraries/actions/Liquidate.sol";
import {BaseTest} from "@test/BaseTest.sol";
import {Vars} from "@test/BaseTest.sol";

import {LoanStatus, RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";
import {Math} from "@src/market/libraries/Math.sol";
import {PERCENT} from "@src/market/libraries/Math.sol";
import {FixedMaturityLimitOrderHelper} from "@test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract LiquidateTest is BaseTest {
    function test_Liquidate_liquidate_repays_loan() public {
        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(liquidator, weth, 100e18);
        _deposit(liquidator, usdc, 100e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 15e6, _maturity(150 days), false);

        _setPrice(0.18e18);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));
        assertEq(size.getLoanStatus(debtPositionId), LoanStatus.ACTIVE);

        _liquidate(liquidator, debtPositionId);

        assertEq(size.getLoanStatus(debtPositionId), LoanStatus.REPAID);
    }

    function test_Liquidate_liquidate_pays_liquidator_reward() public {
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 80e6);
        _deposit(bob, weth, 150e18);
        _deposit(liquidator, usdc, 1_000e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.25e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 80e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        assertEq(_state().bob.debtBalance, futureValue);

        _setPrice(0.7e18);
        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));

        Vars memory _before = _state();

        uint256 assignedCollateral = size.getDebtPositionAssignedCollateral(debtPositionId);
        uint256 debtInCollateralToken = size.debtTokenAmountToCollateralTokenAmount(futureValue);
        uint256 expectedLiquidatorProfit;
        uint256 expectedProtocolProfit;
        if (assignedCollateral > debtInCollateralToken) {
            uint256 liquidatorReward = Math.min(
                assignedCollateral - debtInCollateralToken,
                Math.mulDivUp(debtInCollateralToken, size.feeConfig().liquidationRewardPercent, PERCENT)
            );
            expectedLiquidatorProfit = debtInCollateralToken + liquidatorReward;
            uint256 collateralRemainder = assignedCollateral - expectedLiquidatorProfit;
            uint256 collateralRemainderCap =
                Math.mulDivDown(debtInCollateralToken, size.riskConfig().crLiquidation - PERCENT, PERCENT);
            collateralRemainder = Math.min(collateralRemainder, collateralRemainderCap);
            expectedProtocolProfit =
                Math.mulDivDown(collateralRemainder, size.feeConfig().collateralProtocolPercent, PERCENT);
        } else {
            expectedLiquidatorProfit = assignedCollateral;
            expectedProtocolProfit = 0;
        }

        _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();

        assertEq(
            _after.liquidator.collateralTokenBalance,
            _before.liquidator.collateralTokenBalance + expectedLiquidatorProfit
        );
        assertEq(
            _after.feeRecipient.collateralTokenBalance,
            _before.feeRecipient.collateralTokenBalance + expectedProtocolProfit
        );
    }

    function test_Liquidate_liquidate_reduces_borrower_debt() public {
        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(liquidator, weth, 100e18);
        _deposit(liquidator, usdc, 100e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 amount = 15e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, _maturity(150 days), false);

        _setPrice(0.18e18);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));

        _liquidate(liquidator, debtPositionId);

        assertEq(_state().bob.debtBalance, 0);
    }

    function test_Liquidate_liquidate_can_be_called_unprofitably_and_liquidator_is_senior_creditor() public {
        _setPrice(1e18);

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(liquidator, usdc, 1000e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 amount = 15e6;
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, amount, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        _setPrice(0.1e18);

        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));
        uint256 assignedCollateral = size.getDebtPositionAssignedCollateral(debtPositionId);
        uint256 futureValueCollateral =
            size.debtTokenAmountToCollateralTokenAmount(size.getDebtPosition(debtPositionId).futureValue);

        Vars memory _before = _state();

        uint256 liquidatorProfit = _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();

        assertLt(liquidatorProfit, futureValueCollateral);
        assertEq(liquidatorProfit, assignedCollateral);
        uint256 ratePerTenor = Math.aprToRatePerTenor(0.03e18, 150 days);
        uint256 issuanceValue = Math.mulDivUp(futureValue, PERCENT, PERCENT + ratePerTenor);
        uint256 expectedSwapFee = size.getSwapFee(issuanceValue, 150 days);
        assertEq(_before.feeRecipient.borrowTokenBalance, expectedSwapFee);
        assertEq(_after.feeRecipient.borrowTokenBalance, _before.feeRecipient.borrowTokenBalance);
        assertEq(
            _after.feeRecipient.collateralTokenBalance,
            _before.feeRecipient.collateralTokenBalance,
            "The liquidator receives the collateral remainder first"
        );
        assertEq(size.getDebtPositionAssignedCollateral(debtPositionId), 0);
        assertEq(size.getUserView(bob).collateralTokenBalance, 0);
    }

    function test_Liquidate_liquidate_overdue_well_collateralized() public {
        _updateConfig("minTenor", 1 seconds);
        _updateConfig("maxTenor", 180 days);
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("overdueCollateralProtocolPercent", 0.123e18);
        _updateConfig("crLiquidation", 1.2e18);
        _setPrice(1e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 150e18);
        _deposit(candy, usdc, 100e6);
        _deposit(liquidator, usdc, 1_000e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 50e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        vm.warp(block.timestamp + 150 days + 1);

        Vars memory _before = _state();
        (uint256 loansBefore,) = size.getPositionsCount();
        assertGt(size.getDebtPosition(debtPositionId).futureValue, 0);
        assertTrue(!_isUserUnderwater(bob));

        uint256 debtInCollateralToken = size.debtTokenAmountToCollateralTokenAmount(futureValue);
        uint256 liquidatorReward = Math.min(
            _before.bob.collateralTokenBalance - debtInCollateralToken,
            Math.mulDivUp(debtInCollateralToken, _overdueLiquidationRewardPercent(), PERCENT)
        );
        uint256 liquidatorProfitCollateralToken = debtInCollateralToken + liquidatorReward;

        uint256 protocolSplit = Math.min(
            _before.bob.collateralTokenBalance - liquidatorProfitCollateralToken,
            debtInCollateralToken * (size.riskConfig().crLiquidation - PERCENT) / PERCENT
        ) * size.feeConfig().overdueCollateralProtocolPercent / PERCENT;

        assertTrue(!_isUserUnderwater(bob));
        assertTrue(size.isDebtPositionLiquidatable(debtPositionId));

        _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();
        (uint256 loansAfter,) = size.getPositionsCount();

        assertEq(_after.alice, _before.alice);
        assertEq(loansBefore, loansAfter);
        assertEq(
            _after.bob.collateralTokenBalance,
            _before.bob.collateralTokenBalance - liquidatorProfitCollateralToken - protocolSplit
        );
        assertEq(
            _after.feeRecipient.collateralTokenBalance, _before.feeRecipient.collateralTokenBalance + protocolSplit
        );
        assertEq(
            _after.liquidator.collateralTokenBalance,
            _before.liquidator.collateralTokenBalance + liquidatorProfitCollateralToken
        );
        assertEq(size.getDebtPosition(debtPositionId).futureValue, 0);
        assertLt(_after.bob.debtBalance, _before.bob.debtBalance);
        assertEq(_after.bob.debtBalance, 0);
    }

    function test_Liquidate_liquidate_overdue_uses_overdue_reward_percent() public {
        _updateConfig("minTenor", 1 seconds);
        _updateConfig("maxTenor", 180 days);
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("overdueCollateralProtocolPercent", 0.005e18);
        _updateConfig("overdueLiquidationRewardPercent", 0.01e18);
        _updateConfig("crLiquidation", 1.2e18);
        _setPrice(1e18);

        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 150e18);
        _deposit(candy, usdc, 100e6);
        _deposit(liquidator, usdc, 1_000e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 50e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        vm.warp(block.timestamp + 150 days + 1);

        Vars memory _before = _state();

        uint256 debtInCollateralToken = size.debtTokenAmountToCollateralTokenAmount(futureValue);
        uint256 liquidatorReward = Math.min(
            _before.bob.collateralTokenBalance - debtInCollateralToken,
            Math.mulDivUp(debtInCollateralToken, _overdueLiquidationRewardPercent(), PERCENT)
        );
        uint256 liquidatorProfitCollateralToken = debtInCollateralToken + liquidatorReward;

        uint256 protocolSplit = Math.min(
            _before.bob.collateralTokenBalance - liquidatorProfitCollateralToken,
            debtInCollateralToken * (size.riskConfig().crLiquidation - PERCENT) / PERCENT
        ) * size.feeConfig().overdueCollateralProtocolPercent / PERCENT;

        _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();

        assertEq(
            _after.bob.collateralTokenBalance,
            _before.bob.collateralTokenBalance - liquidatorProfitCollateralToken - protocolSplit
        );
        assertEq(
            _after.liquidator.collateralTokenBalance,
            _before.liquidator.collateralTokenBalance + liquidatorProfitCollateralToken
        );
        assertEq(
            _after.feeRecipient.collateralTokenBalance, _before.feeRecipient.collateralTokenBalance + protocolSplit
        );
        assertEq(_after.bob.debtBalance, 0);
    }

    function test_Liquidate_liquidate_overdue_very_high_CR() public {
        _updateConfig("minTenor", 1 seconds);
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("overdueLiquidationRewardPercent", 0.05e18);
        _updateConfig("overdueCollateralProtocolPercent", 0.005e18);
        _setPrice(1e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 1000e18);
        _deposit(candy, usdc, 100e6);
        _deposit(liquidator, usdc, 1_000e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 50e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        vm.warp(block.timestamp + 150 days + 1);

        Vars memory _before = _state();
        (uint256 loansBefore,) = size.getPositionsCount();

        uint256 assignedCollateral = size.getDebtPositionAssignedCollateral(debtPositionId);
        uint256 debtInCollateralToken = size.debtTokenAmountToCollateralTokenAmount(futureValue);
        uint256 liquidatorProfitCollateralToken;
        if (assignedCollateral > debtInCollateralToken) {
            uint256 liquidatorReward = Math.min(
                assignedCollateral - debtInCollateralToken,
                Math.mulDivUp(debtInCollateralToken, _overdueLiquidationRewardPercent(), PERCENT)
            );
            liquidatorProfitCollateralToken = debtInCollateralToken + liquidatorReward;
        } else {
            liquidatorProfitCollateralToken = assignedCollateral;
        }

        uint256 collateralRemainder = Math.min(
            assignedCollateral - liquidatorProfitCollateralToken,
            Math.mulDivDown(debtInCollateralToken, size.riskConfig().crLiquidation - PERCENT, PERCENT)
        );

        uint256 protocolSplit = collateralRemainder * size.feeConfig().overdueCollateralProtocolPercent / PERCENT;

        _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();
        (uint256 loansAfter,) = size.getPositionsCount();

        assertEq(_after.alice, _before.alice);
        assertEq(loansBefore, loansAfter);
        assertEq(
            _after.bob.collateralTokenBalance,
            _before.bob.collateralTokenBalance - liquidatorProfitCollateralToken - protocolSplit
        );
        assertEq(
            _after.feeRecipient.collateralTokenBalance, _before.feeRecipient.collateralTokenBalance + protocolSplit
        );
        assertEq(
            _after.liquidator.collateralTokenBalance,
            _before.liquidator.collateralTokenBalance + liquidatorProfitCollateralToken
        );
        assertEq(size.getDebtPosition(debtPositionId).futureValue, 0);
        assertLt(_after.bob.debtBalance, _before.bob.debtBalance);
        assertEq(_after.bob.debtBalance, 0);
    }

    function test_Liquidate_liquidate_overdue_should_claim_later_with_interest() public {
        _updateConfig("swapFeeAPR", 0);
        _setPrice(1e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 170e18);
        _deposit(liquidator, usdc, 1_000e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 50e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        uint256 creditId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        vm.warp(block.timestamp + 150 days + 1);

        _liquidate(liquidator, debtPositionId);

        Vars memory _before = _state();

        _setLiquidityIndex(1.1e27);

        Vars memory _interest = _state();

        _claim(alice, creditId);

        Vars memory _after = _state();

        uint256 expectedInterestBalance = Math.mulDivDown(_before.alice.borrowTokenBalance, 1.1e27, 1e27);
        uint256 expectedClaim = Math.mulDivDown(futureValue, 1.1e27, 1e27);
        assertEqApprox(_interest.alice.borrowTokenBalance, expectedInterestBalance, 1);
        assertEqApprox(_after.alice.borrowTokenBalance, _interest.alice.borrowTokenBalance + expectedClaim, 1);
    }

    function test_Liquidate_liquidate_overdue_underwater() public {
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 165e18);
        _deposit(liquidator, usdc, 1_000e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 50e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        vm.warp(block.timestamp + 150 days + 1);
        Vars memory _before = _state();

        _setPrice(0.5e18);

        uint256 debtInCollateralToken = size.debtTokenAmountToCollateralTokenAmount(futureValue);
        uint256 liquidatorReward = Math.min(
            _state().bob.collateralTokenBalance - debtInCollateralToken,
            Math.mulDivUp(debtInCollateralToken, _overdueLiquidationRewardPercent(), PERCENT)
        );
        uint256 liquidatorProfitCollateralToken = debtInCollateralToken + liquidatorReward;

        assertTrue(_isUserUnderwater(bob));
        _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();

        assertEq(
            _after.liquidator.collateralTokenBalance,
            _before.liquidator.collateralTokenBalance + liquidatorProfitCollateralToken
        );
    }

    function testFuzz_Liquidate_liquidate_minimumCollateralProfit(
        uint256 newPrice,
        uint256 interval,
        uint256 minimumCollateralProfit
    ) public {
        _setPrice(1e18);
        newPrice = bound(newPrice, 1, 2e18);
        interval = bound(interval, 0, 2 * 150 days);
        minimumCollateralProfit = bound(minimumCollateralProfit, 1, 200e18);

        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 200e18);
        _deposit(liquidator, usdc, 1_000e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 15e6, _maturity(150 days), false);

        _setPrice(newPrice);
        vm.warp(block.timestamp + interval);

        vm.assume(size.isDebtPositionLiquidatable(debtPositionId));

        Vars memory _before = _state();

        vm.prank(liquidator);
        try size.liquidate(
            LiquidateParams({
                debtPositionId: debtPositionId,
                minimumCollateralProfit: minimumCollateralProfit,
                deadline: type(uint256).max
            })
        ) returns (uint256 liquidatorProfitCollateralToken) {
            Vars memory _after = _state();

            assertGe(liquidatorProfitCollateralToken, minimumCollateralProfit);
            assertGe(_after.liquidator.collateralTokenBalance, _before.liquidator.collateralTokenBalance);
        } catch {}
    }

    function test_Liquidate_example() public {
        _setPrice(1e18);
        _deposit(bob, usdc, 150e6);
        _buyCreditLimit(bob, block.timestamp + 30 days, _pointOfferAtIndex(0, 0.03e18));
        _deposit(alice, weth, 200e18);
        uint256 debtPositionId = _sellCreditMarket(alice, bob, RESERVED_ID, 100e6, _maturity(30 days), false);
        assertGe(size.collateralRatio(alice), size.riskConfig().crOpening);
        assertTrue(!_isUserUnderwater(alice), "borrower should not be underwater");
        vm.warp(block.timestamp + 1 days);
        _setPrice(0.6e18);

        assertTrue(_isUserUnderwater(alice), "borrower should be underwater");
        assertTrue(size.isDebtPositionLiquidatable(debtPositionId), "loan should be liquidatable");

        _deposit(liquidator, usdc, 10_000e6);
        _liquidate(liquidator, debtPositionId);
    }

    function test_Liquidate_overdue_experiment() public {
        // Bob deposits in USDC
        _deposit(bob, usdc, 100e6);
        assertEq(_state().bob.borrowTokenBalance, 100e6);

        // Bob lends as limit order
        _buyCreditLimit(
            bob,
            block.timestamp + 90 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days),
                uint256(0.03e18),
                uint256(60 days),
                uint256(0.03e18),
                uint256(90 days),
                uint256(0.03e18)
            )
        );

        // Alice deposits in WETH
        _deposit(alice, weth, 50e18);

        // Alice borrows as market order from Bob
        _sellCreditMarket(alice, bob, RESERVED_ID, 70e6, _maturity(60 days), false);

        // Move forward the clock as the loan is overdue
        vm.warp(block.timestamp + 90 days);

        // Assert loan conditions
        assertEq(size.getLoanStatus(0), LoanStatus.OVERDUE, "Loan should be overdue");
        (uint256 debtPositionsCount, uint256 creditPositionsCount) = size.getPositionsCount();
        assertEq(debtPositionsCount, 1);
        assertEq(creditPositionsCount, 1);

        assertGt(size.getDebtPosition(0).futureValue, 0, "Loan should not be repaid before moving to the variable pool");
        uint256 aliceCollateralBefore = _state().alice.collateralTokenBalance;
        assertEq(aliceCollateralBefore, 50e18, "Alice should have no locked ETH initially");

        // add funds
        _deposit(liquidator, usdc, 1_000e6);

        // Liquidate Overdue
        _liquidate(liquidator, 0);

        uint256 aliceCollateralAfter = _state().alice.collateralTokenBalance;

        // Assert post-overdue liquidation conditions
        assertEq(size.getDebtPosition(0).futureValue, 0, "Loan should be repaid by moving into the variable pool");
        assertLt(
            aliceCollateralAfter,
            aliceCollateralBefore,
            "Alice should have lost some collateral after the overdue liquidation"
        );
    }

    function test_Liquidate_round_up_should_not_DoS(uint256 price, uint256 collateral) public {
        collateral = bound(collateral, 0, 100e18);
        price = bound(price, 0.1e18, 1e18);
        _setPrice(1e18);
        _deposit(bob, usdc, 150e6);
        _buyCreditLimit(bob, block.timestamp + 30 days, _pointOfferAtIndex(0, 0.03e18));
        _deposit(alice, weth, 200e18 + collateral);
        uint256 debtPositionId = _sellCreditMarket(alice, bob, RESERVED_ID, 100e6, _maturity(30 days), false);
        assertGe(size.collateralRatio(alice), size.riskConfig().crOpening);
        assertTrue(!_isUserUnderwater(alice), "borrower should not be underwater");
        _setPrice(price);

        if (_isUserUnderwater(alice)) {
            _deposit(liquidator, usdc, 10_000e6);
            _liquidate(liquidator, debtPositionId);
        }
    }
}
