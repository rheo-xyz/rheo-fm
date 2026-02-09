// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";

import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

contract BuyCreditLimitTest is BaseTest {
    using OfferLibrary for FixedMaturityLimitOrder;

    function test_BuyCreditLimit_buyCreditLimit_adds_loanOffer_to_orderbook() public {
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        assertTrue(_state().alice.user.loanOffer.isNull());
        _buyCreditLimit(alice, _riskMaturityAtIndex(0), _pointOfferAtIndex(0, 1.01e18));
        assertTrue(!_state().alice.user.loanOffer.isNull());
    }

    function test_BuyCreditLimit_buyCreditLimit_clear_limit_order() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 1_000e6);
        _deposit(bob, weth, 300e18);
        _deposit(candy, weth, 300e18);

        uint256[] memory maturities = new uint256[](2);
        maturities[0] = _riskMaturityAtIndex(0);
        maturities[1] = _riskMaturityAtIndex(1);
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 0.15e18;
        aprs[1] = 0.12e18;

        vm.prank(alice);
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));

        _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _riskMaturityAtIndex(0), false);

        BuyCreditLimitParams memory empty;
        vm.prank(alice);
        size.buyCreditLimit(empty);

        uint256 amount = 100e6;
        uint256 maturity = _riskMaturityAtIndex(0);
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_OFFER.selector, alice));
        size.sellCreditMarket(
            SellCreditMarketParams({
                lender: alice,
                creditPositionId: RESERVED_ID,
                amount: amount,
                maturity: maturity,
                deadline: block.timestamp,
                maxAPR: type(uint256).max,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_BuyCreditLimit_buyCreditLimit_experiment_strategy_speculator() public {
        // The speculator hopes to profit off of interest rate movements, by either:
        // 1. Lending at a high interest rate and exit to other lenders when interest rates drop
        // 2. Borrowing at low interest rate and exit to other borrowers when interest rates rise
        // #### Case 1: Betting on Rates Dropping
        // Lenny the Lender lends 10,000 at 6% interest for ~5 months, with a futureValue slightly above 10,000.
        // One month after Lenny lends, the interest rate to borrow for ~4 months is 4.5%.
        // Lenny exits to another lender, who pays FV/(1+0.045*4/12) to Lenny in return for the FV from the borrower.
        // Lenny has now made a small profit over the course of a month.

        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 10_000e6);
        uint256 maturity = _riskMaturityAtIndex(4);
        uint256 tenor = maturity - block.timestamp;
        _buyCreditLimit(alice, maturity, _pointOfferAtIndex(4, 0.06e18));

        _deposit(bob, weth, 20_000e18);
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 10_000e6, maturity, false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        uint256 expectedFutureValue = 10_000e6 + uint256(10_000e6 * 0.06e18 * tenor) / 365 days / 1e18;
        assertEqApprox(futureValue, expectedFutureValue, 1e6);

        uint256 elapsed = 30 days;
        uint256 remainingTenor = maturity > block.timestamp + elapsed ? maturity - (block.timestamp + elapsed) : 0;
        vm.warp(block.timestamp + elapsed);
        _deposit(candy, usdc, futureValue);
        _buyCreditLimit(candy, maturity, _pointOfferAtIndex(4, 0.045e18));
        _sellCreditMarket(alice, candy, creditPositionId);

        uint256 exitRate = Math.aprToRatePerTenor(0.045e18, remainingTenor);
        uint256 expectedCash = Math.mulDivDown(futureValue, PERCENT, PERCENT + exitRate);
        assertEqApprox(_state().alice.borrowTokenBalance, expectedCash, 10e6);
        assertEq(_state().alice.debtBalance, 0);
    }
}
