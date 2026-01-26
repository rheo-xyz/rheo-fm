// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript} from
    "@script/ProposeSafeTxUpgradeSizeFactoryRemoveMarket.s.sol";
import {Contract, Networks} from "@script/Networks.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {Errors} from "@src/market/libraries/Errors.sol";
import {ForkTest} from "@test/fork/ForkTest.sol";
import {console} from "forge-std/console.sol";

contract ForkRemoveMarketTest is ForkTest, Networks {
    SizeFactory private factory;
    address private factoryOwner;

    function setUp() public override(ForkTest) {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string memory rpcAlias = bytes(alchemyKey).length == 0 ? "base_archive" : "base";
        vm.createSelectFork(rpcAlias);
        vm.chainId(8453);

        factory = SizeFactory(contracts[BASE_MAINNET][Contract.SIZE_FACTORY]);
        factoryOwner = contracts[BASE_MAINNET][Contract.SIZE_GOVERNANCE];

        console.log("ForkRemoveMarketTest: factory", address(factory));
        console.log("ForkRemoveMarketTest: factoryOwner", factoryOwner);
    }

    function testFork_removeMarket_afterUpgrade() public {
        // Get initial markets count
        uint256 initialMarketsCount = factory.getMarketsCount();
        console.log("Initial markets count:", initialMarketsCount);
        assertTrue(initialMarketsCount > 0, "Should have at least one market");

        // Get a market to remove
        ISize marketToRemove = factory.getMarket(0);
        address marketAddress = address(marketToRemove);
        console.log("Market to remove:", marketAddress);

        // Verify the market is currently registered
        assertTrue(factory.isMarket(marketAddress), "Market should be registered before removal");

        // Perform the upgrade
        _upgradeSizeFactory();

        // Verify the market is still registered after upgrade
        assertTrue(factory.isMarket(marketAddress), "Market should still be registered after upgrade");

        // Remove the market
        vm.prank(factoryOwner);
        factory.removeMarket(marketAddress);

        // Verify the market is no longer registered
        assertFalse(factory.isMarket(marketAddress), "Market should not be registered after removal");

        // Verify markets count decreased
        uint256 finalMarketsCount = factory.getMarketsCount();
        assertEq(finalMarketsCount, initialMarketsCount - 1, "Markets count should decrease by 1");

        console.log("Final markets count:", finalMarketsCount);
        console.log("testFork_removeMarket_afterUpgrade: PASSED");
    }

    function testFork_removeMarket_revertsForNonAdmin() public {
        // Perform the upgrade
        _upgradeSizeFactory();

        // Get a market to remove
        ISize marketToRemove = factory.getMarket(0);
        address marketAddress = address(marketToRemove);

        // Try to remove market from non-admin account - should revert
        address nonAdmin = address(0xdead);
        vm.prank(nonAdmin);
        vm.expectRevert();
        factory.removeMarket(marketAddress);
    }

    function testFork_removeMarket_revertsForInvalidMarket() public {
        // Perform the upgrade
        _upgradeSizeFactory();

        // Try to remove a non-existent market - should revert with INVALID_MARKET
        address invalidMarket = address(0xbeef);
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MARKET.selector, invalidMarket));
        factory.removeMarket(invalidMarket);
    }

    function _upgradeSizeFactory() internal {
        ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript script =
            new ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript();
        (address[] memory targets, bytes[] memory datas) = script.getUpgradeSizeFactoryData();

        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(factoryOwner);
            (bool ok,) = targets[i].call(datas[i]);
            assertTrue(ok, "Upgrade call should succeed");
        }
    }
}

