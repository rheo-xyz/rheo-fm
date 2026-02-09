// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";

import {Math} from "@src/market/libraries/Math.sol";
import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";

import {Vars} from "@test/BaseTest.sol";
import {BaseTestGenericMarket} from "@test/BaseTestGenericMarket.sol";
import {FixedMaturityLimitOrderHelper} from "@test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract GenericMarket_cbBTC_USDC_Test is BaseTestGenericMarket {
    function setUp() public virtual override {
        this.setUp_cbBTC_USDC();
    }

    function test_GenericMarket_cbBTC_USDC_decimals() public view {
        assertEq(size.data().collateralToken.decimals(), 8);
        assertEq(size.data().borrowTokenVault.decimals(), 6);
        assertEq(size.data().debtToken.decimals(), 6);
    }

    function test_GenericMarket_cbBTC_USDC_debtTokenAmountToCollateralTokenAmount() public view {
        assertEq(size.debtTokenAmountToCollateralTokenAmount(60576e6), 0.9999e8 + 1);
    }

    function test_GenericMarket_cbBTC_USDC_config() public view {
        assertEqApprox(size.feeConfig().fragmentationFee, 5e6, 0.01e6);
        assertEqApprox(size.riskConfig().minimumCreditBorrowToken, 10e6, 0.01e6);
    }

    function test_GenericMarket_cbBTC_USDC_deposit_eth_reverts() public {
        vm.deal(alice, 1 ether);

        assertEq(address(alice).balance, 1 ether);
        assertEq(_state().alice.borrowTokenBalance, 0);
        assertEq(_state().alice.collateralTokenBalance, 0);

        vm.startPrank(alice);

        vm.expectRevert();
        size.deposit{value: 1 ether}(DepositParams({token: address(weth), amount: 1 ether, to: alice}));
    }

    function test_GenericMarket_cbBTC_USDC_collateralRatio() public {
        _updateConfig("swapFeeAPR", 0);
        _updateConfig("liquidationRewardPercent", 0);

        _deposit(alice, address(borrowToken), 60576e6);
        _deposit(bob, address(collateralToken), 1e8);
        _deposit(liquidator, address(borrowToken), 2 * 60576e6);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.25e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 30288e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        uint256 expectedCR = Math.mulDivDown(
            size.data().collateralToken.balanceOf(bob) * 10 ** borrowToken.decimals(),
            priceFeed.getPrice(),
            size.data().debtToken.balanceOf(bob) * 10 ** collateralToken.decimals()
        );
        assertEqApprox(size.collateralRatio(bob), expectedCR, 0.01e18);

        assertEq(_state().bob.debtBalance, futureValue);

        _setPrice(priceFeed.getPrice() / 3);
        uint256 expectedCRAfter = Math.mulDivDown(
            size.data().collateralToken.balanceOf(bob) * 10 ** borrowToken.decimals(),
            priceFeed.getPrice(),
            size.data().debtToken.balanceOf(bob) * 10 ** collateralToken.decimals()
        );
        assertEqApprox(size.collateralRatio(bob), expectedCRAfter, 0.01e18);

        Vars memory _before = _state();
        uint256 assignedCollateral = size.getDebtPositionAssignedCollateral(debtPositionId);
        uint256 debtInCollateralToken = size.debtTokenAmountToCollateralTokenAmount(futureValue);
        uint256 liquidatorProfitCollateralToken =
            assignedCollateral > debtInCollateralToken ? debtInCollateralToken : assignedCollateral;

        _liquidate(liquidator, debtPositionId);

        Vars memory _after = _state();

        assertEq(
            _after.liquidator.collateralTokenBalance,
            _before.liquidator.collateralTokenBalance + liquidatorProfitCollateralToken
        );
    }
}
