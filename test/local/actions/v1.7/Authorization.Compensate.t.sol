// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {CompensateOnBehalfOfParams, CompensateParams} from "@rheo-fm/src/market/libraries/actions/Compensate.sol";

import {Action, Authorization} from "@rheo-fm/src/factory/libraries/Authorization.sol";
import {BaseTest, Vars} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract AuthorizationCompensateTest is BaseTest {
    function test_AuthorizationCompensate_compensateOnBehalfOf() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.COMPENSATE));

        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(candy, weth, 100e18);
        _deposit(candy, usdc, 100e6);
        _deposit(james, weth, 100e18);
        _deposit(james, usdc, 100e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(james, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 20e6, _maturity(150 days), false);
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
        uint256 debtPositionId2 = _sellCreditMarket(alice, james, RESERVED_ID, 20e6, _maturity(150 days), false);
        uint256 creditPositionId3 = size.getCreditPositionIdsByDebtPositionId(debtPositionId2)[0];

        uint256 repaidLoanDebtBefore = size.getDebtPosition(debtPositionId2).futureValue;
        uint256 compensatedLoanCreditBefore = size.getCreditPosition(creditPositionId).credit;

        vm.prank(candy);
        size.compensateOnBehalfOf(
            CompensateOnBehalfOfParams({
                params: CompensateParams({
                    creditPositionWithDebtToRepayId: creditPositionId3,
                    creditPositionToCompensateId: creditPositionId,
                    amount: type(uint256).max
                }),
                onBehalfOf: alice
            })
        );

        uint256 repaidLoanDebtAfter = size.getDebtPosition(debtPositionId2).futureValue;
        uint256 compensatedLoanCreditAfter = size.getCreditPosition(creditPositionId).credit;

        assertEq(repaidLoanDebtAfter, repaidLoanDebtBefore - futureValue);
        assertEq(compensatedLoanCreditAfter, compensatedLoanCreditBefore);
    }

    function test_AuthorizationCompensate_validation() public {
        _deposit(alice, weth, 100e18);
        _deposit(alice, usdc, 100e6);
        _deposit(bob, weth, 100e18);
        _deposit(bob, usdc, 100e6);
        _deposit(candy, weth, 100e18);
        _deposit(candy, usdc, 100e6);
        _deposit(james, weth, 100e18);
        _deposit(james, usdc, 100e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        _buyCreditLimit(james, block.timestamp + 150 days, _pointOfferAtIndex(4, 1e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 20e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];

        vm.expectRevert(abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.COMPENSATE));
        vm.prank(alice);
        size.compensateOnBehalfOf(
            CompensateOnBehalfOfParams({
                params: CompensateParams({
                    creditPositionWithDebtToRepayId: creditPositionId,
                    creditPositionToCompensateId: creditPositionId,
                    amount: type(uint256).max
                }),
                onBehalfOf: bob
            })
        );
    }
}
