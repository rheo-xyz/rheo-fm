// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {YAMv2} from "@rheo-fm/test/mocks/YAMv2.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {USDC} from "@rheo-fm/test/mocks/USDC.sol";
import {WETH} from "@rheo-fm/test/mocks/WETH.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

contract InitializeValidationTest is Test, BaseTest {
    function test_Initialize_validation() public {
        Rheo implementation = new Rheo();

        address owner = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        owner = address(this);

        f.feeRecipient = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        f.feeRecipient = feeRecipient;

        r.crOpening = 0.5e18;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_RATIO.selector, 0.5e18));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.crOpening = 1.5e18;

        r.crLiquidation = 0.3e18;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_RATIO.selector, 0.3e18));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.crLiquidation = 1.3e18;

        r.crLiquidation = 1.5e18;
        r.crOpening = 1.3e18;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_LIQUIDATION_COLLATERAL_RATIO.selector, 1.3e18, 1.5e18));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.crLiquidation = 1.3e18;
        r.crOpening = 1.5e18;

        f.overdueCollateralProtocolPercent = 1.1e18;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_PERCENTAGE_PREMIUM.selector, 1.1e18));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        f.overdueCollateralProtocolPercent = 0.01e18;

        f.liquidationRewardPercent = 1.1e18;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_AMOUNT.selector, 1.1e18));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        f.liquidationRewardPercent = 0.01e18;

        f.collateralProtocolPercent = 1.2e18;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_COLLATERAL_PERCENTAGE_PREMIUM.selector, 1.2e18));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        f.collateralProtocolPercent = 0.1e18;

        r.minimumCreditBorrowToken = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.minimumCreditBorrowToken = 5e6;

        r.minTenor = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.minTenor = 1 hours;

        r.maxTenor = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.maxTenor = 150 days;

        r.minTenor = r.maxTenor + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, r.minTenor, r.maxTenor));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        r.minTenor = 1 hours;

        r.maturities = new uint256[](0);
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        Rheo emptyMaturitiesRheo = Rheo(address(proxy));
        assertEq(emptyMaturitiesRheo.riskConfig().maturities.length, 0);

        uint256[] memory unorderedMaturities = new uint256[](2);
        unorderedMaturities[0] = block.timestamp + r.minTenor + 2;
        unorderedMaturities[1] = block.timestamp + r.minTenor + 1;
        r.maturities = unorderedMaturities;
        vm.expectRevert(abi.encodeWithSelector(Errors.MATURITIES_NOT_STRICTLY_INCREASING.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));

        uint256[] memory pastMaturities = new uint256[](1);
        pastMaturities[0] = block.timestamp - 1;
        r.maturities = pastMaturities;
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        uint256[] memory outOfRangeMaturities = new uint256[](1);
        outOfRangeMaturities[0] = block.timestamp + r.maxTenor + 1;
        r.maturities = outOfRangeMaturities;
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        uint256[] memory validMaturities = new uint256[](1);
        validMaturities[0] = block.timestamp + r.minTenor;
        r.maturities = validMaturities;

        o.priceFeed = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        o.priceFeed = address(priceFeed);

        d.weth = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.weth = address(weth);

        d.underlyingCollateralToken = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.underlyingCollateralToken = address(weth);

        d.underlyingCollateralToken = address(new YAMv2());
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_DECIMALS.selector, 24));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.underlyingCollateralToken = address(weth);

        d.underlyingBorrowToken = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.underlyingBorrowToken = address(usdc);

        d.underlyingBorrowToken = address(new YAMv2());
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_DECIMALS.selector, 24));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.underlyingBorrowToken = address(usdc);

        d.variablePool = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.variablePool = address(variablePool);

        d.borrowTokenVault = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.borrowTokenVault = address(new NonTransferrableRebasingTokenVault());

        d.sizeFactory = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        d.sizeFactory = address(sizeFactory);
    }
}
