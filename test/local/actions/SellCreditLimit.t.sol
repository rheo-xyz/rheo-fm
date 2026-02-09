// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {DebtPosition} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {BuyCreditMarket, BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

contract SellCreditLimitTest is BaseTest {
    using OfferLibrary for FixedMaturityLimitOrder;

    function test_SellCreditLimit_sellCreditLimit_adds_borrowOffer_to_orderbook() public {
        _deposit(alice, weth, 100e18);
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 60 days;
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 1.01e18;
        aprs[1] = 1.02e18;
        assertTrue(_state().alice.user.borrowOffer.isNull());
        _sellCreditLimit(
            alice, block.timestamp + 150 days, FixedMaturityLimitOrder({maturities: maturities, aprs: aprs})
        );

        assertTrue(!_state().alice.user.borrowOffer.isNull());
    }

    function testFuzz_SellCreditLimit_sellCreditLimit_adds_borrowOffer_to_orderbook(uint256 buckets, bytes32 seed)
        public
    {
        uint256[] memory availableMaturities = size.riskConfig().maturities;
        buckets = bound(buckets, 1, availableMaturities.length);
        uint256[] memory tenors = new uint256[](buckets);
        uint256[] memory aprs = new uint256[](buckets);

        for (uint256 i = 0; i < buckets; i++) {
            tenors[i] = availableMaturities[i] - block.timestamp;
            aprs[i] = bound(uint256(keccak256(abi.encode(seed, i))), 0, 10e18);
        }
        _sellCreditLimit(alice, block.timestamp + 150 days, _offerFromTenors(tenors, aprs));
    }

    function test_SellCreditLimit_sellCreditLimit_cant_be_placed_if_cr_is_below_openingLimitBorrowCR() public {
        _setPrice(1e18);
        _deposit(bob, usdc, 100e6);
        _deposit(alice, weth, 150e18);
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 60 days;
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 0e18;
        aprs[1] = 1e18;
        _setUserConfiguration(alice, 1.7e18, false, false, new uint256[](0));
        _sellCreditLimit(
            alice, block.timestamp + 150 days, FixedMaturityLimitOrder({maturities: maturities, aprs: aprs})
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.CR_BELOW_OPENING_LIMIT_BORROW_CR.selector, alice, 1.5e18, 1.7e18));
        vm.prank(bob);
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                amount: 100e6,
                maturity: block.timestamp + 30 days,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: true,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_SellCreditLimit_sellCreditLimit_cant_be_placed_if_cr_is_below_crOpening_even_if_openingLimitBorrowCR_is_below(
    ) public {
        _setPrice(1e18);
        _deposit(bob, usdc, 100e6);
        _deposit(alice, weth, 140e18);
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 60 days;
        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 0e18;
        aprs[1] = 1e18;
        _setUserConfiguration(alice, 1.3e18, false, false, new uint256[](0));
        _sellCreditLimit(
            alice, block.timestamp + 150 days, FixedMaturityLimitOrder({maturities: maturities, aprs: aprs})
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.CR_BELOW_OPENING_LIMIT_BORROW_CR.selector, alice, 1.4e18, 1.5e18));
        vm.prank(bob);
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                amount: 100e6,
                maturity: block.timestamp + 30 days,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: true,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_SellCreditLimit_sellCreditLimit_experiment_strategy_speculator() public {
        // #### Case 2: Betting on Rates Increasing
        // Bobby the borrower creates a limit offer to borrow at 2%, which gets filled by an exiting borrower for Cash=12,000, FV=12,080 USDC with a remaining term of 4 months.
        // One month later, someone named Sammy offers to borrow at 3.5%
        // Bobby exits to Sammy for the remaining 3 months.
        _setPrice(1e18);
        _updateConfig("swapFeeAPR", 0);

        _deposit(bob, weth, 20_000e18);
        uint256 initialTenor = 120 days;
        uint256 maturity = _maturity(initialTenor);
        _sellCreditLimit(bob, _pointOfferAtIndex(3, 0.02e18));

        _deposit(candy, usdc, 20_000e6);
        uint256 borrowedAmount = 12_000e6;
        uint256 debtPositionId = _buyCreditMarket(candy, bob, borrowedAmount, maturity, true);

        DebtPosition memory debtPosition = size.getDebtPosition(debtPositionId);
        assertEqApprox(debtPosition.futureValue, 12_080e6, 2e6);

        vm.warp(block.timestamp + 30 days);
        _deposit(james, weth, 20_000e18);
        _sellCreditLimit(james, _pointOfferAtIndex(3, 0.035e18));
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: james,
            creditPositionId: RESERVED_ID,
            amount: debtPosition.futureValue,
            maturity: debtPosition.dueDate,
            deadline: block.timestamp,
            minAPR: 0,
            exactAmountIn: false,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        BuyCreditMarket.SwapDataBuyCreditMarket memory expected = size.getBuyCreditMarketSwapData(params);
        uint256 debtPositionId2 = _buyCreditMarket(bob, james, debtPosition.futureValue, debtPosition.dueDate);
        uint256 creditPositionId2 = size.getCreditPositionIdsByDebtPositionId(debtPositionId2)[0];
        _compensate(bob, creditPositionId, creditPositionId2);

        uint256 expectedProfit = borrowedAmount - expected.cashAmountIn;
        assertEqApprox(_state().bob.borrowTokenBalance, expectedProfit, 1e6);
        assertEq(_state().bob.debtBalance, 0);
    }
}
