// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";
import {UserView} from "@rheo-fm/src/market/RheoView.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {CreditPosition, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {
    SetUserConfigurationOnBehalfOfParams,
    SetUserConfigurationParams
} from "@rheo-fm/src/market/libraries/actions/SetUserConfiguration.sol";

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";
import {Action, Authorization} from "@rheo-fm/src/factory/libraries/Authorization.sol";

contract AuthorizationSetUserConfigurationTest is BaseTest {
    function test_AuthorizationSetUserConfiguration_setUserConfigurationOnBehalfOf() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.SET_USER_CONFIGURATION));

        _setPrice(1e18);
        _updateConfig("fragmentationFee", 0);

        _deposit(alice, usdc, 1000e6);
        _deposit(bob, weth, 1600e18);
        _deposit(james, weth, 1600e18);
        _deposit(james, usdc, 1000e6);
        _deposit(candy, usdc, 1200e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(3, 0.05e18));
        _buyCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(4, 0));
        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(3, 0.04e18));

        uint256 tenor = 120 days;
        uint256 debtPositionId1 = _sellCreditMarket(bob, alice, RESERVED_ID, 975.94e6, _maturity(tenor), false);
        uint256 creditPositionId1_1 = size.getCreditPositionIdsByDebtPositionId(debtPositionId1)[0];
        uint256 futureValue = size.getDebtPosition(debtPositionId1).futureValue;

        CreditPosition memory creditPosition = size.getCreditPosition(creditPositionId1_1);
        assertEq(creditPosition.lender, alice);

        uint256[] memory creditPositionIds = new uint256[](1);
        creditPositionIds[0] = creditPositionId1_1;
        vm.prank(candy);
        size.setUserConfigurationOnBehalfOf(
            SetUserConfigurationOnBehalfOfParams({
                params: SetUserConfigurationParams({
                    openingLimitBorrowCR: 0,
                    allCreditPositionsForSaleDisabled: true,
                    creditPositionIdsForSale: false,
                    creditPositionIds: creditPositionIds
                }),
                onBehalfOf: alice
            })
        );

        uint256 maturity = _maturity(tenor);
        vm.expectRevert(abi.encodeWithSelector(Errors.CREDIT_NOT_FOR_SALE.selector, creditPositionId1_1));
        _buyCreditMarket(james, alice, creditPositionId1_1, futureValue, maturity, false);
    }

    function test_AuthorizationSetUserConfiguration_validation() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.SET_USER_CONFIGURATION)
        );
        vm.prank(alice);
        size.setUserConfigurationOnBehalfOf(
            SetUserConfigurationOnBehalfOfParams({
                params: SetUserConfigurationParams({
                    openingLimitBorrowCR: 0,
                    allCreditPositionsForSaleDisabled: true,
                    creditPositionIdsForSale: false,
                    creditPositionIds: new uint256[](0)
                }),
                onBehalfOf: bob
            })
        );
    }
}
