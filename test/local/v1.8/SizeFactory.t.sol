// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {RheoMock} from "@rheo-fm/test/mocks/RheoMock.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";

contract SizeFactoryTest is BaseTest {
    function test_SizeFactory_setSizeImplementation_does_not_change_rheoImplementation() public {
        SizeFactory factory = SizeFactory(payable(address(sizeFactory)));
        address oldRheoImplementation = factory.rheoImplementation();
        address newImplementation = address(new RheoMock());

        factory.setSizeImplementation(newImplementation);

        assertEq(factory.sizeImplementation(), newImplementation);
        assertEq(factory.rheoImplementation(), oldRheoImplementation);
    }

    function test_SizeFactory_markets_registry_helpers() public {
        SizeFactory factory = SizeFactory(payable(address(sizeFactory)));

        assertTrue(factory.isRheoMarket(address(size)));
        assertEq(factory.getMarketsCount(), 1);

        address[] memory markets = factory.getMarkets();
        assertEq(markets.length, 1);
        assertEq(markets[0], address(size));

        factory.removeMarket(address(size));

        assertFalse(factory.isRheoMarket(address(size)));
        assertEq(factory.getMarketsCount(), 0);
        assertEq(factory.getMarkets().length, 0);
    }

    function test_SizeFactory_upgradeToAndCall_authorized() public {
        SizeFactory factory = SizeFactory(payable(address(sizeFactory)));
        address newImplementation = address(new SizeFactory());

        factory.upgradeToAndCall(newImplementation, bytes(""));

        assertEq(factory.getMarketsCount(), 1);
    }
}
