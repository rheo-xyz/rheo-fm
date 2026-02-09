// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {Vars} from "@rheo-fm/test/BaseTest.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";

import {LoanStatus, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {BuyCreditMarket, BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {Math, PERCENT, YEAR} from "@rheo-fm/src/market/libraries/Math.sol";

contract BuyCreditMarketLendTest is BaseTest {
    using OfferLibrary for FixedMaturityLimitOrder;

    uint256 private constant MAX_RATE = 2e18;
    uint256 private constant MAX_AMOUNT_USDC = 100e6;
    uint256 private constant MAX_AMOUNT_WETH = 2e18;

    struct BuyCreditMarketExactAmountOutSpecificationParams {
        uint256 A1;
        uint256 A2;
        uint256 deltaT1;
        uint256 deltaT2;
        uint256 apr1;
        uint256 apr2;
    }

    struct BuyCreditMarketExactAmountInSpecificationParams {
        uint256 V1;
        uint256 V2;
        uint256 deltaT1;
        uint256 deltaT2;
        uint256 apr1;
        uint256 apr2;
    }

    struct BuyCreditMarketSpecificationLocalParams {
        uint256 r1;
        uint256 r2;
        uint256 debtPositionId;
        uint256 creditPositionId;
        uint256 A1;
        uint256 A2;
        uint256 V1;
        uint256 V2;
    }

    struct BuyCreditMarketExactAmountInLocal {
        uint256 maturity;
        uint256 tenor;
        uint256 futureValue;
        uint256 swapFee;
        uint256 loansBefore;
        uint256 loansAfter;
        uint256 debtPositionId;
    }

    function test_BuyCreditMarket_buyCreditMarket_transfers_to_borrower() public {
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        uint256 rate = 0.03e18;
        _sellCreditLimit(alice, block.timestamp + 150 days, rate);

        uint256 tenor = 150 days;
        uint256 ratePerTenor = Math.aprToRatePerTenor(rate, tenor);
        uint256 issuanceValue = 10e6;
        uint256 futureValue = Math.mulDivUp(issuanceValue, PERCENT + ratePerTenor, PERCENT);
        uint256 amountIn = Math.mulDivUp(futureValue, PERCENT, PERCENT + ratePerTenor);

        Vars memory _before = _state();
        (uint256 loansBefore,) = size.getPositionsCount();

        uint256 debtPositionId = _buyCreditMarket(bob, alice, futureValue, _maturity(tenor));

        Vars memory _after = _state();
        (uint256 loansAfter,) = size.getPositionsCount();

        assertEq(
            _after.alice.borrowTokenBalance,
            _before.alice.borrowTokenBalance + amountIn - size.getSwapFee(amountIn, tenor)
        );
        assertEq(_after.bob.borrowTokenBalance, _before.bob.borrowTokenBalance - amountIn);
        assertEq(_after.alice.debtBalance, _before.alice.debtBalance + futureValue);
        assertEq(loansAfter, loansBefore + 1);
        assertEq(size.getDebtPosition(debtPositionId).futureValue, futureValue);
        assertEq(size.getDebtPosition(debtPositionId).dueDate, block.timestamp + tenor);
    }

    function test_BuyCreditMarket_buyCreditMarket_exactAmountIn() public {
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _sellCreditLimit(alice, block.timestamp + 150 days, 0.03e18);

        uint256 amountIn = 10e6;
        uint256 tenor = 150 days;
        uint256 ratePerTenor = Math.aprToRatePerTenor(0.03e18, tenor);
        uint256 futureValue = Math.mulDivDown(amountIn, PERCENT + ratePerTenor, PERCENT);

        Vars memory _before = _state();
        (uint256 loansBefore,) = size.getPositionsCount();

        uint256 debtPositionId = _buyCreditMarket(bob, alice, amountIn, _maturity(tenor), true);

        Vars memory _after = _state();
        (uint256 loansAfter,) = size.getPositionsCount();

        assertEq(
            _after.alice.borrowTokenBalance,
            _before.alice.borrowTokenBalance + amountIn - size.getSwapFee(amountIn, tenor)
        );
        assertEq(_after.bob.borrowTokenBalance, _before.bob.borrowTokenBalance - amountIn);
        assertEq(_after.alice.debtBalance, _before.alice.debtBalance + futureValue);
        assertEq(loansAfter, loansBefore + 1);
        assertEq(size.getDebtPosition(debtPositionId).futureValue, futureValue);
        assertEq(size.getDebtPosition(debtPositionId).dueDate, block.timestamp + tenor);
    }

    function testFuzz_BuyCreditMarket_buyCreditMarket_exactAmountIn(uint256 amountIn, uint256 seed) public {
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        FixedMaturityLimitOrder memory curve = FixedMaturityLimitOrderHelper.getRandomOffer(seed);
        _sellCreditLimit(alice, block.timestamp + 150 days, curve);

        amountIn = bound(amountIn, 5e6, 100e6);
        BuyCreditMarketExactAmountInLocal memory local;
        local.maturity = curve.maturities[0];
        local.tenor = local.maturity - block.timestamp;
        local.futureValue = Math.mulDivDown(
            amountIn,
            PERCENT + Math.aprToRatePerTenor(size.getUserDefinedBorrowOfferAPR(alice, local.maturity), local.tenor),
            PERCENT
        );

        Vars memory _before = _state();
        (local.loansBefore,) = size.getPositionsCount();

        local.debtPositionId = _buyCreditMarket(bob, alice, amountIn, local.maturity, true);

        Vars memory _after = _state();
        (local.loansAfter,) = size.getPositionsCount();

        local.swapFee = size.getSwapFee(amountIn, local.tenor);

        assertEq(_after.alice.borrowTokenBalance, _before.alice.borrowTokenBalance + amountIn - local.swapFee);
        assertEq(_after.bob.borrowTokenBalance, _before.bob.borrowTokenBalance - amountIn);
        assertEq(_after.alice.debtBalance, _before.alice.debtBalance + local.futureValue);
        assertEq(local.loansAfter, local.loansBefore + 1);
        assertEq(size.getDebtPosition(local.debtPositionId).futureValue, local.futureValue);
        assertEq(size.getDebtPosition(local.debtPositionId).dueDate, local.maturity);
    }

    function test_BuyCreditMarket_buyCreditMarket_cannot_leave_borrower_liquidatable() public {
        _setPrice(1e18);
        _deposit(alice, weth, 150e18);
        _deposit(bob, usdc, 200e6);
        _sellCreditLimit(alice, block.timestamp + 150 days, 0);

        uint256 maturity = _maturity(150 days);
        uint256 openingCr = size.riskConfig().crOpening;
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.CR_BELOW_OPENING_LIMIT_BORROW_CR.selector, alice, 0.75e18, openingCr)
        );
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                maturity: maturity,
                amount: 200e6,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_BuyCreditMarket_buyCreditMarket_reverts_if_dueDate_out_of_range() public {
        _setPrice(1e18);
        _deposit(alice, weth, 150e18);
        _deposit(bob, usdc, 200e6);
        FixedMaturityLimitOrder memory curve = FixedMaturityLimitOrderHelper.normalOffer();
        _sellCreditLimit(alice, block.timestamp + 150 days, curve);

        vm.startPrank(bob);
        uint256 minTenor = size.riskConfig().minTenor;
        uint256 maxTenor = size.riskConfig().maxTenor;
        uint256 shortMaturity = block.timestamp + minTenor - 1;
        uint256 longMaturity = block.timestamp + maxTenor + 1;
        vm.expectRevert(
            abi.encodeWithSelector(Errors.MATURITY_OUT_OF_RANGE.selector, shortMaturity, minTenor, maxTenor)
        );
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                maturity: shortMaturity,
                amount: 10e6,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.MATURITY_OUT_OF_RANGE.selector, longMaturity, minTenor, maxTenor));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                maturity: longMaturity,
                amount: 10e6,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                maturity: block.timestamp + 150 days,
                amount: 10e6,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_BuyCreditMarket_buyCreditMarket_experiment_lend_to_borrower() public {
        _setPrice(1e18);
        // Alice deposits in WETH
        _deposit(alice, weth, 200e18);

        // Alice places a borrow limit order
        _sellCreditLimit(
            alice, block.timestamp + 150 days, [int256(0.03e18), int256(0.03e18)], [uint256(30 days), uint256(60 days)]
        );

        // Bob deposits in USDC
        _deposit(bob, usdc, 100e6);
        assertEq(_state().bob.borrowTokenBalance, 100e6);

        // Assert there are no active loans initially
        (uint256 debtPositionsCount, uint256 creditPositionsCount) = size.getPositionsCount();
        assertEq(debtPositionsCount, 0, "There should be no active loans initially");

        // Bob lends to Alice's offer in the market order
        _buyCreditMarket(bob, alice, 70e6, _maturity(30 days));

        // Assert a loan is active after lending
        (debtPositionsCount, creditPositionsCount) = size.getPositionsCount();
        assertEq(debtPositionsCount, 1, "There should be one active loan after lending");
        assertEq(creditPositionsCount, 1, "There should be one active loan after lending");
    }

    function test_BuyCreditMarket_buyCreditMarket_experiment_buy_credit_from_lender() public {
        _setPrice(1e18);
        _updateConfig("fragmentationFee", 0);
        _updateConfig("swapFeeAPR", 0);

        _deposit(alice, usdc, 1000e6);
        _deposit(bob, weth, 1600e18);
        _deposit(james, weth, 1600e18);
        _deposit(james, usdc, 1000e6);
        _deposit(candy, usdc, 1200e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(3, 0.05e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(3, 0.04e18));

        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 975.94e6, _maturity(120 days), false);
        uint256 creditPositionId1_1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1)[0];
        uint256 debtPositionId2 =
            _sellCreditMarket(james, candy, RESERVED_ID, 1000.004274e6, _maturity(150 days), false);
        uint256 creditPositionId2_1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId2)[0];

        uint256 ratePerTenor = Math.aprToRatePerTenor(0.05e18, 120 days);
        uint256 expectedFutureValue = Math.mulDivUp(975.94e6, PERCENT + ratePerTenor, PERCENT);
        assertEq(size.getDebtPosition(debtPositionId1).futureValue, expectedFutureValue);
        assertEq(_state().alice.borrowTokenBalance, 1000e6 - 975.94e6);
        assertEqApprox(_state().james.borrowTokenBalance, 1000e6 + 1000.004274e6, 0.01e6);

        Vars memory _beforeBuy = _state();
        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: address(0),
            creditPositionId: creditPositionId1_1,
            maturity: size.getDebtPosition(debtPositionId1).dueDate,
            amount: size.getDebtPosition(debtPositionId1).futureValue,
            exactAmountIn: false,
            deadline: block.timestamp,
            minAPR: 0,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        BuyCreditMarket.SwapDataBuyCreditMarket memory expected = size.getBuyCreditMarketSwapData(params);
        _buyCreditMarket(james, creditPositionId1_1, params.amount, params.exactAmountIn);

        Vars memory _afterBuy = _state();
        assertEqApprox(
            _afterBuy.james.borrowTokenBalance, _beforeBuy.james.borrowTokenBalance - expected.cashAmountIn, 0.01e6
        );
        assertEq(
            _afterBuy.alice.borrowTokenBalance,
            _beforeBuy.alice.borrowTokenBalance + expected.cashAmountIn - expected.swapFee - expected.fragmentationFee
        );

        uint256 creditPositionId1_2 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1)[0];
        Vars memory _beforeComp = _state();
        _compensate(james, creditPositionId2_1, creditPositionId1_2);

        Vars memory _afterComp = _state();
        assertEq(_afterComp.alice.borrowTokenBalance, _beforeComp.alice.borrowTokenBalance);
    }

    function test_BuyCreditMarket_buyCreditMarket_fee_properties() public {
        _setPrice(1e18);

        _deposit(alice, usdc, 1000e6);
        _deposit(bob, weth, 1600e18);
        _deposit(james, weth, 1600e18);
        _deposit(james, usdc, 1000e6);
        _deposit(candy, usdc, 1200e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 2e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));

        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 creditPositionId1_1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1)[0];

        Vars memory _before = _state();

        uint256 amountIn = 30e6;
        _buyCreditMarket(james, creditPositionId1_1, amountIn, true);

        Vars memory _after = _state();

        uint256 fragmentationFee = size.feeConfig().fragmentationFee;
        uint256 swapFee = size.getSwapFee(amountIn - fragmentationFee, 150 days);
        assertEq(_after.james.borrowTokenBalance, _before.james.borrowTokenBalance - amountIn);
        assertEq(
            _after.alice.borrowTokenBalance, _before.alice.borrowTokenBalance + amountIn - swapFee - fragmentationFee
        );
    }

    function test_BuyCreditMarket_buyCreditMarket_exactAmountIn_numeric_example() public {
        _setPrice(1e18);

        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 200e18);
        _deposit(candy, usdc, 200e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.2e18));
        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days));
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        Vars memory _before = _state();

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: address(0),
            creditPositionId: creditPositionId,
            maturity: size.getDebtPosition(debtPositionId).dueDate,
            amount: 80e6,
            exactAmountIn: true,
            deadline: block.timestamp,
            minAPR: 0,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        BuyCreditMarket.SwapDataBuyCreditMarket memory expected = size.getBuyCreditMarketSwapData(params);

        _buyCreditMarket(candy, creditPositionId, params.amount, params.exactAmountIn);

        Vars memory _after = _state();

        assertEq(
            _after.feeRecipient.borrowTokenBalance,
            _before.feeRecipient.borrowTokenBalance + expected.swapFee + expected.fragmentationFee
        );
        assertEq(_after.candy.borrowTokenBalance, _before.candy.borrowTokenBalance - expected.cashAmountIn);
        assertEq(
            _after.alice.borrowTokenBalance,
            _before.alice.borrowTokenBalance + expected.cashAmountIn - expected.swapFee - expected.fragmentationFee
        );
        assertEq(size.getCreditPositionsByDebtPositionId(debtPositionId)[1].credit, expected.creditAmountOut);
    }

    function test_BuyCreditMarket_buyCreditMarket_exactAmountOut_numeric_example() public {
        _setPrice(1e18);

        _deposit(alice, usdc, 200e6);
        _deposit(bob, weth, 200e18);
        _deposit(candy, usdc, 200e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.2e18));
        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));

        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days));
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        Vars memory _before = _state();

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: address(0),
            creditPositionId: creditPositionId,
            maturity: size.getDebtPosition(debtPositionId).dueDate,
            amount: 88e6,
            exactAmountIn: false,
            deadline: block.timestamp,
            minAPR: 0,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        BuyCreditMarket.SwapDataBuyCreditMarket memory expected = size.getBuyCreditMarketSwapData(params);

        _buyCreditMarket(candy, creditPositionId, params.amount, params.exactAmountIn);

        Vars memory _after = _state();

        assertEq(
            _after.feeRecipient.borrowTokenBalance,
            _before.feeRecipient.borrowTokenBalance + expected.swapFee + expected.fragmentationFee
        );
        assertEq(_after.candy.borrowTokenBalance, _before.candy.borrowTokenBalance - expected.cashAmountIn);
        assertEq(
            _after.alice.borrowTokenBalance,
            _before.alice.borrowTokenBalance + expected.cashAmountIn - expected.swapFee - expected.fragmentationFee
        );
        assertEq(size.getCreditPositionsByDebtPositionId(debtPositionId)[1].credit, expected.creditAmountOut);
    }

    function testFuzz_BuyCreditMarket_buyCreditMarket_exactAmountOut_properties(
        uint256 futureValue,
        uint256 tenor,
        uint256 apr
    ) public {
        _deposit(alice, usdc, MAX_AMOUNT_USDC);
        _deposit(bob, weth, MAX_AMOUNT_WETH);

        apr = bound(apr, 0, MAX_RATE);
        uint256 maturity = _riskMaturityAt(tenor);
        tenor = maturity - block.timestamp;
        futureValue = bound(futureValue, size.riskConfig().minimumCreditBorrowToken, MAX_AMOUNT_USDC);
        uint256 ratePerTenor = Math.aprToRatePerTenor(apr, tenor);

        _sellCreditLimit(bob, maturity, FixedMaturityLimitOrderHelper.pointOffer(tenor, apr));

        Vars memory _before = _state();

        _buyCreditMarket(alice, bob, RESERVED_ID, futureValue, maturity, false);

        uint256 swapFeePercent = Math.mulDivUp(size.feeConfig().swapFeeAPR, tenor, YEAR);
        uint256 cash = Math.mulDivUp(futureValue, PERCENT, ratePerTenor + PERCENT);

        Vars memory _after = _state();

        assertEq(_after.alice.borrowTokenBalance, _before.alice.borrowTokenBalance - cash);
        assertEq(
            _after.bob.borrowTokenBalance,
            _before.bob.borrowTokenBalance + cash - Math.mulDivUp(cash, swapFeePercent, PERCENT)
        );
    }

    function testFuzz_BuyCreditMarket_buyCreditMarket_exactAmountOut_specification(
        BuyCreditMarketExactAmountOutSpecificationParams memory input
    ) public {
        vm.warp(block.timestamp + 30 days);

        _deposit(alice, weth, MAX_AMOUNT_WETH);
        _deposit(bob, usdc, 2 * MAX_AMOUNT_USDC);
        _deposit(candy, usdc, 2 * MAX_AMOUNT_USDC);

        BuyCreditMarketSpecificationLocalParams memory local;

        input.apr1 = bound(input.apr1, 0, MAX_RATE);
        uint256 maturity = _riskMaturityAt(input.deltaT1);
        input.deltaT1 = maturity - block.timestamp;
        input.A1 = bound(input.A1, size.riskConfig().minimumCreditBorrowToken, MAX_AMOUNT_USDC);

        _sellCreditLimit(alice, maturity, FixedMaturityLimitOrderHelper.pointOffer(input.deltaT1, input.apr1));

        local.debtPositionId = _buyCreditMarket(bob, alice, RESERVED_ID, input.A1, maturity, false);
        local.creditPositionId = size.getCreditPositionIdsByDebtPositionId(local.debtPositionId)[0];
        local.V1 = size.getCreditPosition(local.creditPositionId).credit;

        input.deltaT2 = _riskTenorAt(input.deltaT2);
        if (input.deltaT2 > input.deltaT1) {
            input.deltaT2 = input.deltaT1;
        }

        vm.warp(block.timestamp + (input.deltaT1 - input.deltaT2));
        input.apr2 = bound(input.apr2, 0, MAX_RATE);
        local.r2 = Math.aprToRatePerTenor(input.apr2, input.deltaT2);
        input.A2 = bound(input.A2, size.riskConfig().minimumCreditBorrowToken, MAX_AMOUNT_USDC);
        _sellCreditLimit(
            bob, block.timestamp + input.deltaT2, FixedMaturityLimitOrderHelper.pointOffer(input.deltaT2, input.apr2)
        );

        Vars memory _before = _state();

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: address(0),
            creditPositionId: local.creditPositionId,
            amount: input.A2,
            maturity: type(uint256).max,
            deadline: block.timestamp,
            minAPR: 0,
            exactAmountIn: false,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });

        bytes4[3] memory expectedErrors = [
            Errors.NOT_ENOUGH_CASH.selector,
            Errors.NOT_ENOUGH_CREDIT.selector,
            Errors.CREDIT_LOWER_THAN_MINIMUM_CREDIT.selector
        ];

        try size.getBuyCreditMarketSwapData(params) returns (BuyCreditMarket.SwapDataBuyCreditMarket memory expected) {
            vm.prank(candy);
            try size.buyCreditMarket(params) {
                Vars memory _after = _state();
                uint256 fragmentationFee = (input.A2 == local.V1 ? 0 : size.feeConfig().fragmentationFee);

                local.V2 = Math.mulDivDown(input.A2, PERCENT, PERCENT + local.r2) + fragmentationFee; /* f */

                assertEq(expected.borrower, bob);
                assertEq(expected.creditAmountOut, input.A2);
                assertEq(expected.cashAmountIn, _before.candy.borrowTokenBalance - _after.candy.borrowTokenBalance);
                assertGt(expected.swapFee, 0);
                assertEq(expected.fragmentationFee, fragmentationFee);
                assertEq(expected.maturity, block.timestamp + input.deltaT2);

                assertEqApprox(local.V2, _before.candy.borrowTokenBalance - _after.candy.borrowTokenBalance, 1e6);
            } catch (bytes memory err) {
                assertIn(bytes4(err), expectedErrors);
            }
        } catch (bytes memory err) {
            assertIn(bytes4(err), expectedErrors);
        }
    }

    function testFuzz_BuyCreditMarket_buyCreditMarket_exactAmountIn_properties(uint256 cash, uint256 tenor, uint256 apr)
        public
    {
        _deposit(alice, usdc, MAX_AMOUNT_USDC);
        _deposit(bob, weth, MAX_AMOUNT_WETH);

        apr = bound(apr, 0, MAX_RATE);
        uint256 maturity = _riskMaturityAt(tenor);
        tenor = maturity - block.timestamp;
        cash = bound(cash, size.riskConfig().minimumCreditBorrowToken, MAX_AMOUNT_USDC);

        _sellCreditLimit(bob, maturity, FixedMaturityLimitOrderHelper.pointOffer(tenor, apr));

        Vars memory _before = _state();

        _buyCreditMarket(alice, bob, RESERVED_ID, cash, maturity, true);

        uint256 swapFeePercent = Math.mulDivUp(size.feeConfig().swapFeeAPR, tenor, YEAR);

        Vars memory _after = _state();

        assertEq(_after.alice.borrowTokenBalance, _before.alice.borrowTokenBalance - cash);
        assertEq(
            _after.bob.borrowTokenBalance,
            _before.bob.borrowTokenBalance + cash - Math.mulDivUp(cash, swapFeePercent, PERCENT)
        );
    }

    function testFuzz_BuyCreditMarket_buyCreditMarket_exactAmountIn_specification(
        BuyCreditMarketExactAmountInSpecificationParams memory input
    ) public {
        vm.warp(block.timestamp + 30 days);

        _deposit(alice, weth, MAX_AMOUNT_WETH);
        _deposit(bob, usdc, 2 * MAX_AMOUNT_USDC);
        _deposit(candy, usdc, 2 * MAX_AMOUNT_USDC);
        BuyCreditMarketSpecificationLocalParams memory local;

        input.apr1 = bound(input.apr1, 0, MAX_RATE);
        uint256 maturity = _riskMaturityAt(input.deltaT1);
        input.deltaT1 = maturity - block.timestamp;
        input.V1 = bound(input.V1, size.riskConfig().minimumCreditBorrowToken, MAX_AMOUNT_USDC);

        _sellCreditLimit(alice, maturity, FixedMaturityLimitOrderHelper.pointOffer(input.deltaT1, input.apr1));

        local.debtPositionId = _buyCreditMarket(bob, alice, RESERVED_ID, input.V1, maturity, true);
        local.creditPositionId = size.getCreditPositionIdsByDebtPositionId(local.debtPositionId)[0];
        local.A1 = size.getCreditPosition(local.creditPositionId).credit;

        input.deltaT2 = _riskTenorAt(input.deltaT2);
        if (input.deltaT2 > input.deltaT1) {
            input.deltaT2 = input.deltaT1;
        }

        vm.warp(block.timestamp + (input.deltaT1 - input.deltaT2));
        input.apr2 = bound(input.apr2, 0, MAX_RATE);
        local.r2 = Math.aprToRatePerTenor(input.apr2, input.deltaT2);
        input.V2 = bound(input.V2, size.riskConfig().minimumCreditBorrowToken, MAX_AMOUNT_USDC);
        _sellCreditLimit(
            bob, block.timestamp + input.deltaT2, FixedMaturityLimitOrderHelper.pointOffer(input.deltaT2, input.apr2)
        );

        Vars memory _before = _state();

        bytes4[4] memory expectedErrors = [
            Errors.NOT_ENOUGH_CASH.selector,
            Errors.NOT_ENOUGH_CREDIT.selector,
            Errors.CREDIT_LOWER_THAN_MINIMUM_CREDIT.selector,
            Errors.CREDIT_LOWER_THAN_MINIMUM_CREDIT_OPENING.selector
        ];

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: address(0),
            creditPositionId: local.creditPositionId,
            amount: input.V2,
            maturity: type(uint256).max,
            deadline: block.timestamp,
            minAPR: 0,
            exactAmountIn: true,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });

        try size.getBuyCreditMarketSwapData(params) returns (BuyCreditMarket.SwapDataBuyCreditMarket memory expected) {
            vm.prank(candy);
            try size.buyCreditMarket(params) {
                Vars memory _after = _state();

                uint256 Vmax = Math.mulDivUp(local.A1, PERCENT, PERCENT + local.r2);
                uint256 fragmentationFee = (input.V2 == Vmax ? 0 : size.feeConfig().fragmentationFee);

                local.A2 = Math.mulDivDown(input.V2 - fragmentationFee, /* f */ PERCENT + local.r2, PERCENT);

                if (input.V2 == Vmax) {
                    assertEq(size.getCreditPosition(local.creditPositionId).lender, candy);
                    assertEq(
                        local.A2,
                        size.getCreditPositionsByDebtPositionId(local.debtPositionId)[size
                            .getCreditPositionsByDebtPositionId(local.debtPositionId).length - 1].credit
                    );
                } else {
                    assertEqApprox(
                        local.A2,
                        size.getCreditPositionsByDebtPositionId(local.debtPositionId)[size
                            .getCreditPositionsByDebtPositionId(local.debtPositionId).length - 1].credit,
                        1e6
                    );
                }
                assertEq(_after.candy.borrowTokenBalance, _before.candy.borrowTokenBalance - input.V2);

                assertEq(expected.borrower, bob);
                assertEq(expected.creditAmountOut, local.A2);
                assertEq(expected.cashAmountIn, input.V2);
                assertGt(expected.swapFee, 0);
                assertEq(expected.fragmentationFee, fragmentationFee);
                assertEq(expected.maturity, block.timestamp + input.deltaT2);
            } catch (bytes memory err) {
                assertIn(bytes4(err), expectedErrors);
            }
        } catch (bytes memory err) {
            assertIn(bytes4(err), expectedErrors);
        }
    }

    function test_BuyCreditMarket_buyCreditMarket_debtTokenCap_exceeded() public {
        assertEq(size.extSload(bytes32(uint256(28))), bytes32(uint256(type(uint256).max)));

        _updateConfig("debtTokenCap", 10e6);

        assertEq(size.extSload(bytes32(uint256(28))), bytes32(uint256(10e6)));

        _deposit(alice, weth, 100e18);

        _deposit(bob, usdc, 100e6);
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));

        BuyCreditMarketParams memory params = BuyCreditMarketParams({
            borrower: bob,
            creditPositionId: RESERVED_ID,
            amount: 100e6,
            maturity: _maturity(150 days),
            minAPR: 0,
            deadline: block.timestamp + 150 days,
            exactAmountIn: true,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
        BuyCreditMarket.SwapDataBuyCreditMarket memory swapData = size.getBuyCreditMarketSwapData(params);
        uint256 expectedDebt = swapData.creditAmountOut;
        vm.expectRevert(abi.encodeWithSelector(Errors.DEBT_TOKEN_CAP_EXCEEDED.selector, 10e6, expectedDebt));
        vm.prank(alice);
        size.buyCreditMarket(params);
    }
}
