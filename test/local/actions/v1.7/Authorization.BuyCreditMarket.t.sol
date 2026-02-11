// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {BaseTest, Vars} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {CREDIT_POSITION_ID_START, DEBT_POSITION_ID_START} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {
    BuyCreditMarketOnBehalfOfParams,
    BuyCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";
import {Action, Authorization} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

contract AuthorizationBuyCreditMarketTest is BaseTest {
    function test_AuthorizationBuyCreditMarket_buyCreditMarketOnBehalfOf() public {
        _setAuthorization(bob, candy, Authorization.getActionsBitmap(Action.BUY_CREDIT_MARKET));

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _sellCreditLimit(alice, block.timestamp + 150 days, 0.03e18);

        uint256 tenor = 150 days;
        uint256 maturity = block.timestamp + tenor;
        (uint256 futureValue, uint256 amountIn) = _computeBuyCreditMarketValues(tenor);

        Vars memory _before = _state();
        uint256 loansBefore = _loansCount();

        (uint256 debtPositionId, uint256 creditPositionId) = _buyCreditMarketOnBehalfOf(amountIn, maturity);

        Vars memory _after = _state();

        assertEq(
            _after.alice.borrowTokenBalance,
            _before.alice.borrowTokenBalance + amountIn - size.getSwapFee(amountIn, tenor)
        );
        assertEq(_after.bob.borrowTokenBalance, _before.bob.borrowTokenBalance - amountIn);
        assertEq(_after.alice.debtBalance, _before.alice.debtBalance + futureValue);
        assertEq(_loansCount(), loansBefore + 1);
        assertEq(size.getDebtPosition(debtPositionId).futureValue, futureValue);
        assertEq(size.getCreditPosition(creditPositionId).lender, candy);
        assertEq(size.getDebtPosition(debtPositionId).dueDate, maturity);
    }

    function test_AuthorizationBuyCreditMarket_validation() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.BUY_CREDIT_MARKET)
        );
        vm.prank(alice);
        size.buyCreditMarketOnBehalfOf(
            BuyCreditMarketOnBehalfOfParams({
                params: BuyCreditMarketParams({
                    borrower: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 100e6,
                    maturity: block.timestamp + 150 days,
                    deadline: block.timestamp,
                    minAPR: 0,
                    exactAmountIn: true,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                }),
                onBehalfOf: bob,
                recipient: candy
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        vm.prank(alice);
        size.buyCreditMarketOnBehalfOf(
            BuyCreditMarketOnBehalfOfParams({
                params: BuyCreditMarketParams({
                    borrower: address(0),
                    creditPositionId: RESERVED_ID,
                    amount: 100e6,
                    maturity: block.timestamp + 150 days,
                    deadline: block.timestamp,
                    minAPR: 0,
                    exactAmountIn: true,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                }),
                onBehalfOf: alice,
                recipient: address(0)
            })
        );
    }

    function _computeBuyCreditMarketValues(uint256 tenor)
        internal
        pure
        returns (uint256 futureValue, uint256 amountIn)
    {
        uint256 issuanceValue = 10e6;
        uint256 ratePerTenor = Math.aprToRatePerTenor(0.03e18, tenor);
        futureValue = Math.mulDivUp(issuanceValue, PERCENT + ratePerTenor, PERCENT);
        amountIn = Math.mulDivUp(futureValue, PERCENT, PERCENT + ratePerTenor);
    }

    function _buyCreditMarketOnBehalfOf(uint256 amountIn, uint256 maturity)
        internal
        returns (uint256 debtPositionId, uint256 creditPositionId)
    {
        vm.prank(candy);
        size.buyCreditMarketOnBehalfOf(
            BuyCreditMarketOnBehalfOfParams({
                params: BuyCreditMarketParams({
                    borrower: alice,
                    creditPositionId: RESERVED_ID,
                    amount: amountIn,
                    maturity: maturity,
                    deadline: block.timestamp,
                    minAPR: 0,
                    exactAmountIn: true,
                    collectionId: RESERVED_ID,
                    rateProvider: address(0)
                }),
                onBehalfOf: bob,
                recipient: candy
            })
        );

        (uint256 debtPositionsCount, uint256 creditPositionsCount) = size.getPositionsCount();
        debtPositionId = DEBT_POSITION_ID_START + debtPositionsCount - 1;
        creditPositionId = CREDIT_POSITION_ID_START + creditPositionsCount - 1;
    }

    function _loansCount() internal view returns (uint256 loansCount) {
        (loansCount,) = size.getPositionsCount();
    }
}
