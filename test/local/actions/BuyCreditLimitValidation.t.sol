// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

import {FixedMaturityLimitOrder, OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

contract BuyCreditLimitValidationTest is BaseTest {
    using OfferLibrary for FixedMaturityLimitOrder;

    function test_BuyCreditLimit_validation() public {
        _deposit(alice, usdc, 100e6);
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = _riskMaturityAtIndex(0);
        maturities[1] = _riskMaturityAtIndex(1);
        uint256[] memory rates1 = new uint256[](1);
        rates1[0] = 1.01e18;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.ARRAY_LENGTHS_MISMATCH.selector));
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: rates1}));

        uint256[] memory empty;

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ARRAY.selector));
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: empty}));

        uint256[] memory aprs = new uint256[](2);
        aprs[0] = 1.01e18;
        aprs[1] = 1.02e18;

        maturities[0] = _riskMaturityAtIndex(1);
        maturities[1] = _riskMaturityAtIndex(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.MATURITIES_NOT_STRICTLY_INCREASING.selector));
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));

        maturities[0] = block.timestamp + 6 minutes;
        maturities[1] = _riskMaturityAtIndex(0);
        uint256 minTenor = size.riskConfig().minTenor;
        uint256 maxTenor = size.riskConfig().maxTenor;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.MATURITY_OUT_OF_RANGE.selector, block.timestamp + 6 minutes, minTenor, maxTenor
            )
        );
        size.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));

        maturities[0] = _riskMaturityAtIndex(0);
        maturities[1] = _riskMaturityAtIndex(1);

        vm.warp(block.timestamp + 3);

        vm.expectRevert(abi.encodeWithSelector(Errors.PAST_MATURITY.selector, 2));
        size.buyCreditLimit(BuyCreditLimitParams({maturities: _singleMaturityArray(2), aprs: _singleAprArray(aprs[0])}));

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ARRAY.selector));
        size.buyCreditLimit(BuyCreditLimitParams({maturities: empty, aprs: aprs}));
    }

    function _singleMaturityArray(uint256 maturity) private pure returns (uint256[] memory maturities) {
        maturities = new uint256[](1);
        maturities[0] = maturity;
    }

    function _singleAprArray(uint256 apr) private pure returns (uint256[] memory aprs) {
        aprs = new uint256[](1);
        aprs[0] = apr;
    }
}
