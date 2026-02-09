// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript} from
    "@rheo-fm/script/ProposeSafeTxUpgradeRheoFactoryRemoveMarket.s.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";
import {console} from "forge-std/console.sol";

contract ForkRemoveMarketTest is ForkTest, Networks {
    RheoFactory private factory;
    address private factoryOwner;

    function setUp() public override(ForkTest) {
        vm.createSelectFork("base_archive", 41515430);

        factory = RheoFactory(contracts[BASE_MAINNET][Contract.RHEO_FACTORY]);
        factoryOwner = contracts[BASE_MAINNET][Contract.RHEO_GOVERNANCE];

        console.log("ForkRemoveMarketTest: factory", address(factory));
        console.log("ForkRemoveMarketTest: factoryOwner", factoryOwner);
    }

    function testFork_RemoveMarket_after_upgrade_removes_active_market() public {
        // Get initial markets count
        uint256 initialMarketsCount = factory.getMarketsCount();
        console.log("Initial markets count:", initialMarketsCount);
        assertTrue(initialMarketsCount > 0, "Should have at least one market");

        // Get a non-paused market to remove so the upgrade doesn't remove it.
        IRheo marketToRemove = _findMarket(false);
        if (address(marketToRemove) == address(0)) {
            console.log("No active market found, skipping test");
            return;
        }
        address marketAddress = address(marketToRemove);
        console.log("Market to remove:", marketAddress);

        // Verify the market is currently registered
        assertTrue(factory.isMarket(marketAddress), "Market should be registered before removal");

        // Perform the upgrade
        _upgradeRheoFactory();

        uint256 postUpgradeMarketsCount = factory.getMarketsCount();
        console.log("Post-upgrade markets count:", postUpgradeMarketsCount);

        // Verify the market is still registered after upgrade
        assertTrue(factory.isMarket(marketAddress), "Market should still be registered after upgrade");

        // Remove the market
        vm.prank(factoryOwner);
        factory.removeMarket(marketAddress);

        // Verify the market is no longer registered
        assertFalse(factory.isMarket(marketAddress), "Market should not be registered after removal");

        // Verify markets count decreased
        uint256 finalMarketsCount = factory.getMarketsCount();
        assertEq(finalMarketsCount, postUpgradeMarketsCount - 1, "Markets count should decrease by 1");

        console.log("Final markets count:", finalMarketsCount);
        console.log("testFork_RemoveMarket_after_upgrade_removes_active_market: PASSED");
    }

    function testFork_RemoveMarket_reverts_for_non_admin() public {
        // Perform the upgrade
        _upgradeRheoFactory();

        // Get a market to remove
        IRheo marketToRemove = factory.getMarket(0);
        address marketAddress = address(marketToRemove);

        // Try to remove market from non-admin account - should revert
        address nonAdmin = address(0xdead);
        vm.prank(nonAdmin);
        vm.expectRevert();
        factory.removeMarket(marketAddress);
    }

    function testFork_RemoveMarket_reverts_for_invalid_market() public {
        // Perform the upgrade
        _upgradeRheoFactory();

        // Try to remove a non-existent market - should revert with INVALID_MARKET
        address invalidMarket = address(0xbeef);
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MARKET.selector, invalidMarket));
        factory.removeMarket(invalidMarket);
    }

    function testFork_RemoveMarket_withdraw_from_removed_market_reverts() public {
        // Find a paused market (expired PT market)
        IRheo pausedMarket = _findMarket(true);
        assertTrue(address(pausedMarket) != address(0), "Paused market should exist");

        address marketAddress = address(pausedMarket);
        console.log("Found paused market:", marketAddress);

        address testUser = address(0x1234);
        IERC20Metadata underlyingBorrowToken = pausedMarket.data().underlyingBorrowToken;
        uint256 depositAmount = 100 * 10 ** underlyingBorrowToken.decimals();

        // First, unpause the market temporarily to deposit funds
        vm.prank(factoryOwner);
        IRheoAdmin(marketAddress).unpause();
        console.log("Market temporarily unpaused for deposit");

        // Deal tokens to test user and deposit into the market
        deal(address(underlyingBorrowToken), testUser, depositAmount);

        vm.startPrank(testUser);
        underlyingBorrowToken.approve(marketAddress, depositAmount);
        pausedMarket.deposit(
            DepositParams({token: address(underlyingBorrowToken), amount: depositAmount, to: testUser})
        );
        vm.stopPrank();
        console.log("Deposited into market");

        // Verify user has balance in the vault
        uint256 vaultBalance = pausedMarket.data().borrowTokenVault.balanceOf(testUser);
        console.log("User vault balance:", vaultBalance);
        assertTrue(vaultBalance > 0, "User should have vault balance after deposit");

        // Now pause the market again (simulating expired PT market state)
        vm.prank(factoryOwner);
        IRheoAdmin(marketAddress).pause();
        console.log("Market re-paused");

        // Upgrade removes paused markets from the factory
        _upgradeRheoFactory();
        console.log("Factory upgraded (paused markets removed)");

        // Verify market is no longer registered
        assertFalse(factory.isMarket(marketAddress), "Market should not be registered after removal");

        // Unpause the market (this is the scenario: admin unpauases removed market)
        vm.prank(factoryOwner);
        IRheoAdmin(marketAddress).unpause();
        console.log("Market unpaused after removal");

        // Verify market is unpaused
        assertFalse(PausableUpgradeable(marketAddress).paused(), "Market should be unpaused");

        // Try to withdraw from the removed market
        // This should revert with UNAUTHORIZED because the vault's onlyMarket modifier
        // checks sizeFactory.isMarket(msg.sender) which returns false
        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(Errors.UNAUTHORIZED.selector, marketAddress));
        pausedMarket.withdraw(
            WithdrawParams({token: address(underlyingBorrowToken), amount: depositAmount, to: testUser})
        );

        console.log("testFork_RemoveMarket_withdraw_from_removed_market_reverts: PASSED");
    }

    function _upgradeRheoFactory() internal {
        ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript script =
            new ProposeSafeTxUpgradeRheoFactoryRemoveMarketScript();
        (address[] memory targets, bytes[] memory datas) = script.getUpgradeRheoFactoryData();

        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(factoryOwner);
            (bool ok,) = targets[i].call(datas[i]);
            assertTrue(ok, "Upgrade call should succeed");
        }
    }

    function _findMarket(bool paused) internal view returns (IRheo) {
        uint256 marketsCount = factory.getMarketsCount();
        for (uint256 i = 0; i < marketsCount; i++) {
            IRheo market = factory.getMarket(i);
            if (PausableUpgradeable(address(market)).paused() == paused) {
                return market;
            }
        }
        return IRheo(address(0));
    }
}
