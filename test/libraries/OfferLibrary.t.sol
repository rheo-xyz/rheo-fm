// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Errors} from "@src/market/libraries/Errors.sol";
import {FixedMaturityLimitOrder, OfferLibrary} from "@src/market/libraries/OfferLibrary.sol";
import {Test} from "forge-std/Test.sol";

contract OfferLibraryTest is Test {
    using EnumerableSet for EnumerableSet.UintSet;
    using OfferLibrary for FixedMaturityLimitOrder;

    EnumerableSet.UintSet private allowedMaturities;

    function test_OfferLibrary_isNull() public pure {
        FixedMaturityLimitOrder memory l;
        assertEq(OfferLibrary.isNull(l), true);

        FixedMaturityLimitOrder memory b;
        assertEq(OfferLibrary.isNull(b), true);
    }

    function test_OfferLibrary_validateLimitOrder_reverts_when_maturities_set_empty() public {
        FixedMaturityLimitOrder memory order =
            FixedMaturityLimitOrder({maturities: _singleMaturity(block.timestamp + 30 days), aprs: _singleApr(0.1e18)});

        vm.expectRevert(Errors.NULL_ARRAY.selector);
        this.callValidateLimitOrder(order, 1 hours, 365 days);
    }

    function test_OfferLibrary_validateLimitOrder_reverts_when_maturity_not_allowed() public {
        allowedMaturities.add(block.timestamp + 30 days);

        uint256 invalidMaturity = block.timestamp + 60 days;
        FixedMaturityLimitOrder memory order =
            FixedMaturityLimitOrder({maturities: _singleMaturity(invalidMaturity), aprs: _singleApr(0.1e18)});

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MATURITY.selector, invalidMaturity));
        this.callValidateLimitOrder(order, 1 hours, 365 days);
    }

    function callValidateLimitOrder(FixedMaturityLimitOrder calldata order, uint256 minTenor, uint256 maxTenor)
        external
        view
    {
        order.validateLimitOrder(allowedMaturities, minTenor, maxTenor);
    }

    function _singleMaturity(uint256 maturity) private pure returns (uint256[] memory maturities) {
        maturities = new uint256[](1);
        maturities[0] = maturity;
    }

    function _singleApr(uint256 apr) private pure returns (uint256[] memory aprs) {
        aprs = new uint256[](1);
        aprs[0] = apr;
    }
}
