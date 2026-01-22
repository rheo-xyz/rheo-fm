// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.sol";

import {FixedMaturityLimitOrder, OfferLibrary} from "@src/market/libraries/OfferLibrary.sol";

import {SellCreditLimitParams} from "@src/market/libraries/actions/SellCreditLimit.sol";

import {Errors} from "@src/market/libraries/Errors.sol";

contract SellCreditLimitValidationTest is BaseTest {
    using OfferLibrary for FixedMaturityLimitOrder;

    function test_SellCreditLimit_validation() public {
        _deposit(alice, weth, 100e18);
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = _riskMaturityAtIndex(0);
        maturities[1] = _riskMaturityAtIndex(1);
        uint256[] memory rates1 = new uint256[](1);
        rates1[0] = 1.01e18;

        vm.expectRevert(abi.encodeWithSelector(Errors.ARRAY_LENGTHS_MISMATCH.selector));
        size.sellCreditLimit(SellCreditLimitParams({maturities: maturities, aprs: rates1}));

        uint256[] memory empty;

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ARRAY.selector));
        size.sellCreditLimit(SellCreditLimitParams({maturities: maturities, aprs: empty}));

        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 1.01e18;
        aprs[1] = 1.02e18;

        maturities[0] = _riskMaturityAtIndex(1);
        maturities[1] = _riskMaturityAtIndex(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.MATURITIES_NOT_STRICTLY_INCREASING.selector));
        size.sellCreditLimit(SellCreditLimitParams({maturities: maturities, aprs: aprs}));

        maturities[0] = block.timestamp + 6 minutes;
        maturities[1] = _riskMaturityAtIndex(0);
        uint256 minTenor = size.riskConfig().minTenor;
        uint256 maxTenor = size.riskConfig().maxTenor;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.MATURITY_OUT_OF_RANGE.selector, block.timestamp + 6 minutes, minTenor, maxTenor
            )
        );
        size.sellCreditLimit(SellCreditLimitParams({maturities: maturities, aprs: aprs}));
    }
}
