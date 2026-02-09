// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Math, PERCENT, YEAR} from "@rheo-fm/src/market/libraries/Math.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";

import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";

contract UpdateConfigTest is BaseTest {
    function test_UpdateConfig_updateConfig_reverts_if_not_owner() public {
        vm.startPrank(alice);

        assertTrue(size.riskConfig().minimumCreditBorrowToken != 1e6);

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, 0x00));
        size.updateConfig(UpdateConfigParams({key: "minimumCreditBorrowToken", value: 1e6}));

        assertTrue(size.riskConfig().minimumCreditBorrowToken != 1e6);
    }

    function test_UpdateConfig_updateConfig_updates_riskConfig() public {
        assertTrue(size.riskConfig().minimumCreditBorrowToken != 1e6);

        size.updateConfig(UpdateConfigParams({key: "minimumCreditBorrowToken", value: 1e6}));

        assertTrue(size.riskConfig().minimumCreditBorrowToken == 1e6);
    }

    function test_UpdateConfig_updateConfig_addMaturity() public {
        uint256[] memory maturities = size.riskConfig().maturities;
        assertGt(maturities.length, 0);

        uint256 maxMaturity = block.timestamp + size.riskConfig().maxTenor;
        uint256 candidate = maturities[0] + 1;
        if (candidate > maxMaturity) {
            candidate = maturities[0];
        }

        bool alreadyPresent = _arrayContains(maturities, candidate);

        size.updateConfig(UpdateConfigParams({key: "addMaturity", value: candidate}));

        uint256[] memory updated = size.riskConfig().maturities;
        if (alreadyPresent) {
            assertEq(updated.length, maturities.length);
        } else {
            assertEq(updated.length, maturities.length + 1);
        }
        assertTrue(_arrayContains(updated, candidate));
    }

    function test_UpdateConfig_updateConfig_cannot_maliciously_liquidate_all_positions() public {
        size.updateConfig(UpdateConfigParams({key: "crOpening", value: 10.0e18}));
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_RATIO.selector, 9.99e18));
        size.updateConfig(UpdateConfigParams({key: "crLiquidation", value: 9.99e18}));
    }

    function test_UpdateConfig_updateConfig_updates_feeConfig() public {
        assertTrue(size.feeConfig().collateralProtocolPercent != 0.456e18);
        size.updateConfig(UpdateConfigParams({key: "collateralProtocolPercent", value: 0.456e18}));
        assertTrue(size.feeConfig().collateralProtocolPercent == 0.456e18);

        assertTrue(_overdueLiquidationRewardPercent() != 0.01e18);
        size.updateConfig(UpdateConfigParams({key: "overdueLiquidationRewardPercent", value: 0.01e18}));
        assertTrue(_overdueLiquidationRewardPercent() == 0.01e18);

        assertTrue(size.feeConfig().feeRecipient != address(this));
        size.updateConfig(UpdateConfigParams({key: "feeRecipient", value: uint256(uint160(address(this)))}));
        assertTrue(size.feeConfig().feeRecipient == address(this));
    }

    function test_UpdateConfig_updateConfig_updates_oracle() public {
        PriceFeedMock newPriceFeed = new PriceFeedMock(address(this));
        assertTrue(size.oracle().priceFeed != address(newPriceFeed));
        size.updateConfig(UpdateConfigParams({key: "priceFeed", value: uint256(uint160(address(newPriceFeed)))}));
        assertTrue(size.oracle().priceFeed == address(newPriceFeed));
    }

    function test_UpdateConfig_updateConfig_should_not_DoS_when_maturities_are_past() public {
        uint256[] memory maturities = size.riskConfig().maturities;
        assertGt(maturities.length, 2);

        vm.warp(maturities[1] + 1);
        assertLt(maturities[0], block.timestamp);
        assertLt(maturities[1], block.timestamp);
        assertGt(maturities[2], block.timestamp);

        uint256 beforeLength = size.riskConfig().maturities.length;

        uint256 maxSwapFeeAPR = Math.mulDivDown(PERCENT, YEAR, size.riskConfig().maxTenor);
        assertGt(maxSwapFeeAPR, 1);
        uint256 nextSwapFeeAPR = size.feeConfig().swapFeeAPR + 1;
        if (nextSwapFeeAPR >= maxSwapFeeAPR) {
            nextSwapFeeAPR = maxSwapFeeAPR - 1;
        }
        size.updateConfig(UpdateConfigParams({key: "swapFeeAPR", value: nextSwapFeeAPR}));
        assertEq(size.feeConfig().swapFeeAPR, nextSwapFeeAPR);

        size.updateConfig(UpdateConfigParams({key: "removeMaturity", value: maturities[0]}));
        uint256[] memory afterFirst = size.riskConfig().maturities;
        assertEq(afterFirst.length, beforeLength - 1);
        for (uint256 i = 0; i < afterFirst.length; i++) {
            assertTrue(afterFirst[i] != maturities[0]);
        }

        size.updateConfig(UpdateConfigParams({key: "removeMaturity", value: maturities[1]}));
        uint256[] memory afterSecond = size.riskConfig().maturities;
        assertEq(afterSecond.length, beforeLength - 2);
        for (uint256 i = 0; i < afterSecond.length; i++) {
            assertTrue(afterSecond[i] != maturities[1]);
        }
    }

    function _arrayContains(uint256[] memory values, uint256 value) private pure returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }
}
