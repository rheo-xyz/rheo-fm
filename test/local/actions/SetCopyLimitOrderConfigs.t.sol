// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {OfferLibrary} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {BuyCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";

import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";
import {SetCopyLimitOrderConfigsParams} from "@rheo-fm/src/market/libraries/actions/SetCopyLimitOrderConfigs.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

contract SetCopyLimitOrderConfigsTest is BaseTest {
    CopyLimitOrderConfig private nullCopy;
    CopyLimitOrderConfig private fullCopy = CopyLimitOrderConfig({
        minTenor: 0,
        maxTenor: type(uint256).max,
        minAPR: 0,
        maxAPR: type(uint256).max,
        offsetAPR: 0
    });

    uint256 private constant MIN = 0;
    uint256 private constant MAX = 255;

    function test_SetCopyLimitOrderConfigs_setCopyLimitOrderConfigs_config() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 borrowOfferAPR = size.getUserDefinedBorrowOfferAPR(bob, block.timestamp + 30 days);
        assertEq(borrowOfferAPR, 0.05e18);

        uint256 loanOfferAPR = size.getUserDefinedLoanOfferAPR(bob, block.timestamp + 60 days);
        assertEq(loanOfferAPR, 0.08e18);

        _setCopyLimitOrderConfigs(
            alice,
            CopyLimitOrderConfig({
                minTenor: 0,
                maxTenor: type(uint256).max,
                minAPR: 0,
                maxAPR: type(uint256).max,
                offsetAPR: 0.01e18
            }),
            CopyLimitOrderConfig({
                minTenor: 0,
                maxTenor: type(uint256).max,
                minAPR: 0,
                maxAPR: type(uint256).max,
                offsetAPR: -0.01e18
            })
        );

        (CopyLimitOrderConfig memory copyLoanOfferConfig, CopyLimitOrderConfig memory copyBorrowOfferConfig) =
            size.getUserDefinedCopyLimitOrderConfigs(alice);
        assertEq(copyLoanOfferConfig.minTenor, fullCopy.minTenor);
        assertEq(copyLoanOfferConfig.maxTenor, fullCopy.maxTenor);
        assertEq(copyLoanOfferConfig.minAPR, fullCopy.minAPR);
        assertEq(copyLoanOfferConfig.maxAPR, fullCopy.maxAPR);
        assertEq(copyLoanOfferConfig.offsetAPR, 0.01e18);
        assertEq(copyBorrowOfferConfig.minTenor, fullCopy.minTenor);
        assertEq(copyBorrowOfferConfig.maxTenor, fullCopy.maxTenor);
        assertEq(copyBorrowOfferConfig.minAPR, fullCopy.minAPR);
        assertEq(copyBorrowOfferConfig.maxAPR, fullCopy.maxAPR);
        assertEq(copyBorrowOfferConfig.offsetAPR, -0.01e18);
    }

    function test_SetCopyLimitOrderConfigs_setCopyLimitOrderConfigs_reset_copy() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        _setCopyLimitOrderConfigs(alice, fullCopy, fullCopy);
        _setCopyLimitOrderConfigs(alice, nullCopy, nullCopy);

        (CopyLimitOrderConfig memory copyLoanOfferConfig, CopyLimitOrderConfig memory copyBorrowOfferConfig) =
            size.getUserDefinedCopyLimitOrderConfigs(alice);
        assertEq(copyLoanOfferConfig.minTenor, 0);
        assertEq(copyLoanOfferConfig.maxTenor, 0);
        assertEq(copyLoanOfferConfig.minAPR, 0);
        assertEq(copyLoanOfferConfig.maxAPR, 0);
        assertEq(copyLoanOfferConfig.offsetAPR, 0);
        assertEq(copyBorrowOfferConfig.minTenor, 0);
        assertEq(copyBorrowOfferConfig.maxTenor, 0);
        assertEq(copyBorrowOfferConfig.minAPR, 0);
        assertEq(copyBorrowOfferConfig.maxAPR, 0);
        assertEq(copyBorrowOfferConfig.offsetAPR, 0);
    }

    function testFuzz_SetCopyLimitOrderConfigs_setCopyLimitOrderConfigs_invariants(
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig
    ) public {
        copyLoanOfferConfig.minTenor = bound(copyLoanOfferConfig.minTenor, MIN, MAX);
        copyLoanOfferConfig.maxTenor = bound(copyLoanOfferConfig.maxTenor, MIN, MAX);
        copyLoanOfferConfig.minAPR = bound(copyLoanOfferConfig.minAPR, MIN, MAX);
        copyLoanOfferConfig.maxAPR = bound(copyLoanOfferConfig.maxAPR, MIN, MAX);
        copyLoanOfferConfig.offsetAPR = bound(copyLoanOfferConfig.offsetAPR, -int256(MAX), int256(MAX));
        copyBorrowOfferConfig.minTenor = bound(copyBorrowOfferConfig.minTenor, MIN, MAX);
        copyBorrowOfferConfig.maxTenor = bound(copyBorrowOfferConfig.maxTenor, MIN, MAX);
        copyBorrowOfferConfig.minAPR = bound(copyBorrowOfferConfig.minAPR, MIN, MAX);
        copyBorrowOfferConfig.maxAPR = bound(copyBorrowOfferConfig.maxAPR, MIN, MAX);
        copyBorrowOfferConfig.offsetAPR = bound(copyBorrowOfferConfig.offsetAPR, -int256(MAX), int256(MAX));

        vm.prank(alice);
        try size.setCopyLimitOrderConfigs(
            SetCopyLimitOrderConfigsParams({
                copyLoanOfferConfig: copyLoanOfferConfig,
                copyBorrowOfferConfig: copyBorrowOfferConfig
            })
        ) {
            assertTrue(!OfferLibrary.isNull(copyLoanOfferConfig) || !OfferLibrary.isNull(copyBorrowOfferConfig));
        } catch (bytes memory) {}
    }
}
