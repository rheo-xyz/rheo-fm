// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.sol";

import {Errors} from "@src/market/libraries/Errors.sol";

import {RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT, YEAR} from "@src/market/libraries/Math.sol";
import {BuyCreditMarketParams} from "@src/market/libraries/actions/BuyCreditMarket.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

contract UpdateConfigValidationTest is BaseTest {
    function test_UpdateConfig_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_KEY.selector, "invalid"));
        size.updateConfig(UpdateConfigParams({key: "invalid", value: 1e18}));

        uint256 crLiquidation = size.riskConfig().crLiquidation;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_RATIO.selector, crLiquidation + 1));
        size.updateConfig(UpdateConfigParams({key: "crLiquidation", value: crLiquidation + 1}));

        uint256 invalidMaturity = block.timestamp + size.riskConfig().minTenor - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.MATURITY_OUT_OF_RANGE.selector,
                invalidMaturity,
                size.riskConfig().minTenor,
                size.riskConfig().maxTenor
            )
        );
        size.updateConfig(UpdateConfigParams({key: "addMaturity", value: invalidMaturity}));

        vm.expectRevert(abi.encodeWithSelector(Errors.PAST_MATURITY.selector, block.timestamp));
        size.updateConfig(UpdateConfigParams({key: "addMaturity", value: block.timestamp}));

        uint256 missingMaturity = block.timestamp + 45 days;
        uint256 maturitiesLength = size.riskConfig().maturities.length;
        size.updateConfig(UpdateConfigParams({key: "removeMaturity", value: missingMaturity}));
        assertEq(size.riskConfig().maturities.length, maturitiesLength);

        uint256 maxSwapFeeAPR = Math.mulDivDown(PERCENT, YEAR, size.riskConfig().maxTenor);
        vm.expectRevert(abi.encodeWithSelector(Errors.VALUE_GREATER_THAN_MAX.selector, maxSwapFeeAPR, maxSwapFeeAPR));
        size.updateConfig(UpdateConfigParams({key: "swapFeeAPR", value: maxSwapFeeAPR}));

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_PERCENTAGE_PREMIUM.selector, PERCENT + 1));
        size.updateConfig(UpdateConfigParams({key: "overdueLiquidationRewardPercent", value: PERCENT + 1}));

        uint256 maxTenor = size.riskConfig().maxTenor;
        size.updateConfig(UpdateConfigParams({key: "minTenor", value: maxTenor}));
        assertEq(size.riskConfig().minTenor, maxTenor);

        uint256 maxTenorForFee = Math.mulDivDown(YEAR, PERCENT, size.feeConfig().swapFeeAPR);
        vm.expectRevert(abi.encodeWithSelector(Errors.VALUE_GREATER_THAN_MAX.selector, maxTenorForFee, maxTenorForFee));
        size.updateConfig(UpdateConfigParams({key: "minTenor", value: maxTenorForFee}));

        vm.expectRevert(abi.encodeWithSelector(Errors.VALUE_GREATER_THAN_MAX.selector, maxTenorForFee, maxTenorForFee));
        size.updateConfig(UpdateConfigParams({key: "maxTenor", value: maxTenorForFee}));

        uint256[] memory maturities = size.riskConfig().maturities;
        for (uint256 i = 0; i < maturities.length; i++) {
            size.updateConfig(UpdateConfigParams({key: "removeMaturity", value: maturities[i]}));
        }
        assertEq(size.riskConfig().maturities.length, 0);

        uint256 maturity = block.timestamp + size.riskConfig().minTenor;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MATURITY.selector, maturity));
        size.buyCreditMarket(
            BuyCreditMarketParams({
                borrower: alice,
                creditPositionId: RESERVED_ID,
                maturity: maturity,
                amount: 1e6,
                deadline: block.timestamp,
                minAPR: 0,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
    }

    function test_UpdateConfig_riskConfigParams_returns_sorted_maturities() public {
        uint256[] memory maturities = size.riskConfig().maturities;
        assertGt(maturities.length, 1);

        size.updateConfig(UpdateConfigParams({key: "removeMaturity", value: maturities[1]}));

        uint256[] memory updated = size.riskConfig().maturities;
        for (uint256 i = 1; i < updated.length; i++) {
            assertLe(updated[i - 1], updated[i]);
        }
    }

    function test_UpdateConfig_updateConfig_cannot_update_data() public {
        address variablePool = address(size.data().variablePool);
        address newVariablePool = makeAddr("newVariablePool");
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_KEY.selector, "variablePool"));
        size.updateConfig(UpdateConfigParams({key: "variablePool", value: uint256(uint160(newVariablePool))}));
        assertEq(address(size.data().variablePool), variablePool);
    }
}
