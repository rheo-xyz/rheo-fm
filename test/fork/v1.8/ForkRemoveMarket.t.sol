// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Contract, Networks} from "@script/Networks.sol";
import {ProposeSafeTxUpgradeSizeFactoryRemoveMarketScript} from
    "@script/ProposeSafeTxUpgradeSizeFactoryRemoveMarket.s.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";
import {Errors} from "@src/market/libraries/Errors.sol";
import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";
import {WithdrawParams} from "@src/market/libraries/actions/Withdraw.sol";
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

    function testFork_removeMarket_withdrawFromRemovedMarketReverts() public {
        // Perform the upgrade first
        _upgradeSizeFactory();

        // Find a paused market (expired PT market)
        ISize pausedMarket = _findPausedMarket();
        if (address(pausedMarket) == address(0)) {
            console.log("No paused market found, skipping test");
            return;
        }

        address marketAddress = address(pausedMarket);
        console.log("Found paused market:", marketAddress);

        address testUser = address(0x1234);
        IERC20Metadata underlyingBorrowToken = pausedMarket.data().underlyingBorrowToken;
        uint256 depositAmount = 100 * 10 ** underlyingBorrowToken.decimals();

        // First, unpause the market temporarily to deposit funds
        vm.prank(factoryOwner);
        ISizeAdmin(marketAddress).unpause();
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
        ISizeAdmin(marketAddress).pause();
        console.log("Market re-paused");

        // Remove the market from factory
        vm.prank(factoryOwner);
        factory.removeMarket(marketAddress);
        console.log("Market removed from factory");

        // Verify market is no longer registered
        assertFalse(factory.isMarket(marketAddress), "Market should not be registered after removal");

        // Unpause the market (this is the scenario: admin unpauases removed market)
        vm.prank(factoryOwner);
        ISizeAdmin(marketAddress).unpause();
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

        console.log("testFork_removeMarket_withdrawFromRemovedMarketReverts: PASSED");
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

    function _findPausedMarket() internal view returns (ISize) {
        uint256 marketsCount = factory.getMarketsCount();
        for (uint256 i = 0; i < marketsCount; i++) {
            ISize market = factory.getMarket(i);
            if (PausableUpgradeable(address(market)).paused()) {
                return market;
            }
        }
        return ISize(address(0));
    }
}
