// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Errors} from "@src/market/libraries/Errors.sol";
import {Math, PERCENT, YEAR} from "@src/market/libraries/Math.sol";
import {BaseTest} from "@test/BaseTest.sol";
import {PriceFeedMock} from "@test/mocks/PriceFeedMock.sol";

import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

import {Size} from "@src/market/Size.sol";

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

        uint256 maxSwapFeeAPR = Math.mulDivDown(PERCENT, YEAR, size.riskConfig().maxTenor);
        assertGt(maxSwapFeeAPR, 1);
        uint256 nextSwapFeeAPR = size.feeConfig().swapFeeAPR + 1;
        if (nextSwapFeeAPR >= maxSwapFeeAPR) {
            nextSwapFeeAPR = maxSwapFeeAPR - 1;
        }
        size.updateConfig(UpdateConfigParams({key: "swapFeeAPR", value: nextSwapFeeAPR}));
        assertEq(size.feeConfig().swapFeeAPR, nextSwapFeeAPR);
    }
}
