// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.sol";

import {Errors} from "@src/market/libraries/Errors.sol";

import {LoanStatus, RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";
import {BuyCreditMarketParams} from "@src/market/libraries/actions/BuyCreditMarket.sol";

contract BuyCreditMarketTest is BaseTest {
    function test_BuyCreditMarket_validation() public {
        _updateConfig("fragmentationFee", 1e6);
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
        _sellCreditLimit(alice, block.timestamp + 30 days, 0.03e18);
        _sellCreditLimit(bob, block.timestamp + 30 days, 0.03e18);
        _sellCreditLimit(candy, block.timestamp + 30 days, 0.03e18);
        _sellCreditLimit(james, block.timestamp + 150 days, 0.03e18);
        uint256 debtPositionId = _buyCreditMarket(alice, candy, RESERVED_ID, 40e6, maturity30, false);

        uint256 deadline = block.timestamp;
        uint256 amount = 50e6;
        uint256 maturity = maturity30;
        bool exactAmountIn = false;

        vm.startPrank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_OFFER.selector, liquidator));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: liquidator,
                creditPositionId: RESERVED_ID,
                amount: amount,
                maturity: maturity,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.startPrank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: address(0),
                creditPositionId: RESERVED_ID,
                amount: amount,
                maturity: maturity,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                amount: 0,
                maturity: maturity,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.PAST_MATURITY.selector, block.timestamp));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                amount: 100e6,
                maturity: block.timestamp,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CREDIT_LOWER_THAN_MINIMUM_CREDIT_OPENING.selector,
                1e6,
                size.riskConfig().minimumCreditBorrowToken
            )
        );
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: james,
                creditPositionId: RESERVED_ID,
                amount: 1e6,
                maturity: maturity150,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.stopPrank();
        vm.startPrank(james);

        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: address(0),
                creditPositionId: creditPositionId,
                amount: 20e6,
                maturity: type(uint256).max,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        vm.startPrank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.NOT_ENOUGH_CREDIT.selector, 100e6, 20e6));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: bob,
                creditPositionId: creditPositionId,
                amount: 100e6,
                maturity: maturity30,
                deadline: deadline,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        vm.stopPrank();

        vm.startPrank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.PAST_DEADLINE.selector, deadline - 1));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: james,
                creditPositionId: RESERVED_ID,
                amount: 20e6,
                maturity: maturity30,
                deadline: deadline - 1,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        vm.stopPrank();

        uint256 apr = size.getUserDefinedBorrowOfferAPR(james, maturity150);

        vm.startPrank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.APR_LOWER_THAN_MIN_APR.selector, apr, apr + 1));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: james,
                creditPositionId: RESERVED_ID,
                amount: 20e6,
                maturity: maturity150,
                deadline: deadline,
                minAPR: apr + 1,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        vm.stopPrank();

        _sellCreditLimit(bob, block.timestamp + 150 days, 0);
        _sellCreditLimit(candy, block.timestamp + 150 days, 0);
        uint256 debtPositionId2 = _buyCreditMarket(alice, candy, RESERVED_ID, 10e6, maturity150, false);
        creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId2)[0];
        _repay(candy, debtPositionId2, candy);

        uint256 cr = size.collateralRatio(candy);

        vm.startPrank(candy);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CREDIT_POSITION_NOT_TRANSFERRABLE.selector, creditPositionId, LoanStatus.REPAID, cr
            )
        );
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: bob,
                creditPositionId: creditPositionId,
                amount: 10e6,
                maturity: maturity150,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 60 days);

        uint256 shortMaturity = _riskMaturityAtIndex(2);
        uint256 invalidMaturity = _riskMaturityAtIndex(3);
        _sellCreditLimit(james, shortMaturity, 0.03e18);
        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MATURITY.selector, invalidMaturity));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: james,
                creditPositionId: RESERVED_ID,
                amount: 10e6,
                maturity: invalidMaturity,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: exactAmountIn,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }
}
