// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {SetCopyLimitOrderConfigsParams} from "@rheo-fm/src/market/libraries/actions/SetCopyLimitOrderConfigs.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract SetCopyLimitOrderConfigsValidationTest is BaseTest {
    CopyLimitOrderConfig private nullCopy;
    CopyLimitOrderConfig private fullCopy = CopyLimitOrderConfig({
        minTenor: 0,
        maxTenor: type(uint256).max,
        minAPR: 0,
        maxAPR: type(uint256).max,
        offsetAPR: 0
    });

    function test_SetCopyLimitOrderConfigs_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, 90 days, 30 days));
        _setCopyLimitOrderConfigs(
            alice,
            CopyLimitOrderConfig({minTenor: 90 days, maxTenor: 30 days, minAPR: 0, maxAPR: 0, offsetAPR: 0}),
            nullCopy
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, 120 days, 60 days));
        _setCopyLimitOrderConfigs(
            alice,
            nullCopy,
            CopyLimitOrderConfig({minTenor: 120 days, maxTenor: 60 days, minAPR: 0, maxAPR: 0, offsetAPR: 0})
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_APR_RANGE.selector, 0.1e18, 0.05e18));
        _setCopyLimitOrderConfigs(
            alice,
            CopyLimitOrderConfig({
                minTenor: 0,
                maxTenor: type(uint256).max,
                minAPR: 0.1e18,
                maxAPR: 0.05e18,
                offsetAPR: 0
            }),
            fullCopy
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_APR_RANGE.selector, 0.2e18, 0.1e18));
        _setCopyLimitOrderConfigs(
            alice,
            fullCopy,
            CopyLimitOrderConfig({
                minTenor: 0,
                maxTenor: type(uint256).max,
                minAPR: 0.2e18,
                maxAPR: 0.1e18,
                offsetAPR: 0
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.INVALID_OFFER_CONFIGS.selector,
                90 days,
                150 days,
                0.06e18,
                0.08e18,
                30 days,
                120 days,
                0.03e18,
                0.05e18
            )
        );
        _setCopyLimitOrderConfigs(
            alice,
            CopyLimitOrderConfig({minTenor: 30 days, maxTenor: 120 days, minAPR: 0.03e18, maxAPR: 0.05e18, offsetAPR: 0}),
            CopyLimitOrderConfig({minTenor: 90 days, maxTenor: 150 days, minAPR: 0.06e18, maxAPR: 0.08e18, offsetAPR: 0})
        );
    }
}
