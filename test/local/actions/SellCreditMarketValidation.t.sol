// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {LoanStatus, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

contract SellCreditMarketValidationTest is BaseTest {
    function test_SellCreditMarket_validation() public {
        _updateConfig("fragmentationFee", 1e6);
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(candy, weth, 100e18);
        _deposit(candy, usdc, 100e6);
        _deposit(james, weth, 100e18);
        _deposit(james, usdc, 100e6);
        uint256 maturity30 = _maturity(30 days);
        uint256 maturity150 = _maturity(150 days);
        _buyCreditLimit(
            alice, block.timestamp + 60 days, [int256(0.03e18), int256(0.03e18)], [uint256(30 days), uint256(60 days)]
        );
        _buyCreditLimit(
            bob, block.timestamp + 60 days, [int256(0.03e18), int256(0.03e18)], [uint256(30 days), uint256(60 days)]
        );
        _buyCreditLimit(candy, block.timestamp + 30 days, _pointOfferAtIndex(0, 0.03e18));
        _buyCreditLimit(
            james, block.timestamp + 150 days, [int256(0.03e18), int256(0.03e18)], [uint256(30 days), uint256(150 days)]
        );
        uint256 debtPositionId = _sellCreditMarket(alice, candy, RESERVED_ID, 40e6, maturity30, false);

        uint256 deadline = block.timestamp;
        bool exactAmountIn = false;

        {
            uint256 amount = 50e6;
            vm.startPrank(candy);
            vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: address(0),
                    creditPositionId: RESERVED_ID,
                    amount: amount,
                    maturity: maturity30,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );

            vm.startPrank(candy);
            vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_OFFER.selector, liquidator));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: liquidator,
                    creditPositionId: RESERVED_ID,
                    amount: amount,
                    maturity: maturity30,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );

            vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 0,
                    maturity: maturity30,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );

            vm.expectRevert(abi.encodeWithSelector(Errors.PAST_MATURITY.selector, block.timestamp));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 100e6,
                    maturity: block.timestamp,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
        }

        {
            uint256 invalidMaturity = block.timestamp + 45 days;
            vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MATURITY.selector, invalidMaturity));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 20e6,
                    maturity: invalidMaturity,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
        }

        {
            uint256 ratePerTenor = Math.aprToRatePerTenor(0.03e18, 150 days);
            uint256 expectedCredit = Math.mulDivUp(1e6, PERCENT + ratePerTenor, PERCENT);
            vm.expectRevert(
                abi.encodeWithSelector(
                    Errors.CREDIT_LOWER_THAN_MINIMUM_CREDIT_OPENING.selector,
                    expectedCredit,
                    size.riskConfig().minimumCreditBorrowToken
                )
            );
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: james,
                    creditPositionId: RESERVED_ID,
                    amount: 1e6,
                    maturity: maturity150,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
        }

        vm.stopPrank();
        vm.startPrank(james);

        {
            uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
            vm.expectRevert(abi.encodeWithSelector(Errors.BORROWER_IS_NOT_LENDER.selector, james, candy));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: creditPositionId,
                    amount: 20e6,
                    maturity: block.timestamp + 30 days,
                    deadline: deadline,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );

            vm.startPrank(candy);
            vm.expectRevert(abi.encodeWithSelector(Errors.APR_GREATER_THAN_MAX_APR.selector, 0.03e18, 0.01e18));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: james,
                    creditPositionId: creditPositionId,
                    amount: 20e6,
                    maturity: type(uint256).max,
                    deadline: deadline,
                    maxAPR: 0.01e18,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
            vm.stopPrank();

            vm.startPrank(candy);
            vm.expectRevert(abi.encodeWithSelector(Errors.PAST_DEADLINE.selector, deadline - 1));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: james,
                    creditPositionId: creditPositionId,
                    amount: 20e6,
                    maturity: type(uint256).max,
                    deadline: deadline - 1,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
            vm.stopPrank();
        }

        {
            _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
            _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
            uint256 debtPositionId2 = _sellCreditMarket(alice, candy, RESERVED_ID, 10e6, maturity150, false);
            uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId2)[0];
            uint256 credit = size.getCreditPosition(creditPositionId).credit;

            vm.startPrank(candy);
            vm.expectRevert(abi.encodeWithSelector(Errors.NOT_ENOUGH_CREDIT.selector, 1000e6, credit));
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: bob,
                    creditPositionId: creditPositionId,
                    amount: 1000e6,
                    maturity: maturity150,
                    deadline: block.timestamp,
                    maxAPR: type(uint256).max,
                    exactAmountIn: true,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
            vm.stopPrank();

            _repay(alice, debtPositionId2, alice);

            uint256 cr = size.collateralRatio(alice);

            vm.startPrank(candy);
            vm.expectRevert(
                abi.encodeWithSelector(
                    Errors.CREDIT_POSITION_NOT_TRANSFERRABLE.selector, creditPositionId, LoanStatus.REPAID, cr
                )
            );
            size.sellCreditMarket(
                SellCreditMarketParams({
                    lender: bob,
                    creditPositionId: creditPositionId,
                    amount: 10e6,
                    maturity: maturity150,
                    deadline: block.timestamp,
                    maxAPR: type(uint256).max,
                    exactAmountIn: exactAmountIn,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                })
            );
            vm.stopPrank();
        }
    }
}
