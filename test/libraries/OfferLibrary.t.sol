// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {FixedMaturityLimitOrder, OfferLibrary} from "@src/market/libraries/OfferLibrary.sol";
import {Test} from "forge-std/Test.sol";

contract OfferLibraryTest is Test {
    function test_OfferLibrary_isNull() public pure {
        FixedMaturityLimitOrder memory l;
        assertEq(OfferLibrary.isNull(l), true);

        FixedMaturityLimitOrder memory b;
        assertEq(OfferLibrary.isNull(b), true);
    }
}
