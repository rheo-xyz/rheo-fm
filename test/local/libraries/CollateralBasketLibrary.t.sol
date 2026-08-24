// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@rheo-fm/src/market/libraries/Math.sol";

import {BaseTestBasket} from "@rheo-fm/test/local/actions/basket/BaseTestBasket.sol";

/// @title CollateralBasketLibraryTest
/// @notice Tier 0 of the test plan: the basket valuation maths, exercised through the market's views
/// @dev The fixture lists WETH (18 dec), A (18 dec @ 200), B (8 dec @ 61,000) and C (6 dec @ 1) against the
///      6-decimal USDC borrow token, which is the decimals spread the product cares about.
contract CollateralBasketLibraryTest is BaseTestBasket {
    // --- exactness fixtures ---

    function test_CollateralBasketLibrary_value_is_exact_across_decimals() public view {
        assertEq(size.getCollateralAssetValue(address(assetA), 1e18), 200e6);
        assertEq(size.getCollateralAssetValue(address(assetA), 0.5e18), 100e6);
        assertEq(size.getCollateralAssetValue(address(assetB), 1e8), 61_000e6);
        // one base unit of an 8-decimal asset at 61,000 is still worth 610 borrow base units
        assertEq(size.getCollateralAssetValue(address(assetB), 1), 610);
        assertEq(size.getCollateralAssetValue(address(assetC), 1e6), 1e6);
    }

    function test_CollateralBasketLibrary_up_is_never_below_down_and_differs_by_at_most_one() public view {
        uint256[3] memory amounts = [uint256(1), 12_345, 7e17];

        for (uint256 i = 0; i < amounts.length; i++) {
            _assertUpDownBound(address(assetA), amounts[i]);
            _assertUpDownBound(address(assetB), amounts[i]);
            _assertUpDownBound(address(assetC), amounts[i]);
        }
    }

    /// @dev A single wei of an 18-decimal asset is worth far less than one borrow base unit, so it floors to
    ///      zero while rounding up to one. This is the gap the explicit-seizure check relies on: a griefer
    ///      picking dust across assets is charged the round-up value.
    function test_CollateralBasketLibrary_rounding_gap_is_visible_on_dust() public view {
        assertEq(size.getCollateralAssetValue(address(assetA), 1), 0);
        assertEq(size.getCollateralAssetValueUp(address(assetA), 1), 1);
    }

    // --- fuzz ---

    function testFuzz_CollateralBasketLibrary_up_bounds_down(uint256 amount) public view {
        amount = bound(amount, 0, 1e30);
        _assertUpDownBound(address(assetA), amount);
        _assertUpDownBound(address(assetB), amount);
        _assertUpDownBound(address(assetC), amount);
    }

    function testFuzz_CollateralBasketLibrary_value_is_monotonic(uint256 a, uint256 b) public view {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);
        if (a > b) {
            (a, b) = (b, a);
        }
        assertLe(size.getCollateralAssetValue(address(assetA), a), size.getCollateralAssetValue(address(assetA), b));
        assertLe(size.getCollateralAssetValue(address(assetB), a), size.getCollateralAssetValue(address(assetB), b));
    }

    /// @dev Valuing separately then summing can lose at most one base unit against valuing the total
    function testFuzz_CollateralBasketLibrary_value_is_additive_within_rounding(uint256 a, uint256 b) public view {
        a = bound(a, 0, 1e28);
        b = bound(b, 0, 1e28);

        uint256 separate =
            size.getCollateralAssetValue(address(assetB), a) + size.getCollateralAssetValue(address(assetB), b);
        uint256 together = size.getCollateralAssetValue(address(assetB), a + b);

        assertLe(separate, together);
        assertGe(separate + 1, together);
    }

    /// @dev collateralValue is the sum over the basket of each holding's round-down value
    function testFuzz_CollateralBasketLibrary_collateralValue_sums_the_basket(uint256 amountA, uint256 amountC) public {
        amountA = bound(amountA, 0, 1e24);
        amountC = bound(amountC, 0, 1e12);

        if (amountA > 0) {
            _deposit(alice, assetA, amountA);
        }
        if (amountC > 0) {
            _deposit(alice, assetC, amountC);
        }

        uint256 expected = size.getCollateralAssetValue(address(assetA), amountA)
            + size.getCollateralAssetValue(address(assetC), amountC);
        assertEq(size.collateralValue(alice), expected);
    }

    /// @dev Zero-balance assets are skipped, so an account holding nothing is worth nothing regardless of how
    ///      many assets the market lists
    function test_CollateralBasketLibrary_empty_account_is_worth_zero() public view {
        assertEq(size.collateralValue(alice), 0);
    }

    function _assertUpDownBound(address underlying, uint256 amount) private view {
        uint256 down = size.getCollateralAssetValue(underlying, amount);
        uint256 up = size.getCollateralAssetValueUp(underlying, amount);
        assertGe(up, down);
        assertLe(up, down + 1);
    }
}
