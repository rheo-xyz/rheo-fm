// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {singleCollateralAsset} from "@rheo-fm/script/CollateralAssets.sol";

import {IPool} from "@aave/interfaces/IPool.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {
    AAVE_ADAPTER_ID,
    DEFAULT_VAULT,
    ERC4626_ADAPTER_ID,
    NonTransferrableRebasingTokenVault
} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {AaveAdapter} from "@rheo-fm/src/market/token/adapters/AaveAdapter.sol";
import {ERC4626Adapter} from "@rheo-fm/src/market/token/adapters/ERC4626Adapter.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {PauseAll} from "@rheo-fm/src/protection/PauseAll.sol";

import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";
import {ISizeFactory, PAUSER_ROLE} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Test} from "forge-std/Test.sol";

/// @title ArbitrumPauseAllOwnershipHandoffForkTest
/// @notice Phase 9.2 + 9.3 — proves the two-step ownership handoff from the Safe to the
///         Hypernative bot works end-to-end:
///           1. Safe deploys PauseAll (initial owner = Safe).
///           2. Safe is granted PAUSER_ROLE on the factory.
///           3. Safe calls `transferOwnership(bot)`. pendingOwner = bot, owner still = Safe.
///           4. Bot calls `acceptOwnership()`. owner = bot.
///           5. Bot can now call `pauseAll()`. Safe can no longer.
///
///         Run: `FOUNDRY_PROFILE=fork forge test --mc ArbitrumPauseAllOwnershipHandoffForkTest -vvv`
contract ArbitrumPauseAllOwnershipHandoffForkTest is Test, Networks {
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address private constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;
    address private hypernativeBot;

    SizeFactory private sizeFactory;
    NonTransferrableRebasingTokenVault private borrowTokenVault;
    AaveAdapter private aaveAdapter;
    ERC4626Adapter private erc4626Adapter;
    IPriceFeed private priceFeed;
    IRheo private market;
    PauseAll private pauseAll;
    NetworkConfiguration private cfg;

    function setUp() public {
        try vm.envString("API_KEY_ALCHEMY") returns (string memory) {
            vm.createSelectFork("arbitrum-production");
        } catch {
            vm.createSelectFork("arbitrum_archive");
        }
        cfg = params("arbitrum-production-weth-usdc");
        hypernativeBot = makeAddr("hypernativeBot");

        sizeFactory = SizeFactory(payable(contracts[ARBITRUM_MAINNET][Contract.RHEO_FACTORY]));
        require(address(sizeFactory).code.length > 0, "live SizeFactory not deployed at registered address");

        _ensureWired();
        _phase2_CreateBorrowVaultAndAdapters();
        _phase3_DeployPriceFeed();
        _phase5_CreateMarket();
        _phase7_DeployPauseAll();
        _phase8_GrantPauserRole();
    }

    function _ensureWired() internal {
        Rheo rheoImpl = new Rheo();
        NonTransferrableRebasingTokenVault vaultImpl = new NonTransferrableRebasingTokenVault();
        CollectionsManager cmImpl = new CollectionsManager();
        CollectionsManager cmProxy = CollectionsManager(
            address(
                new ERC1967Proxy(
                    address(cmImpl), abi.encodeCall(CollectionsManager.initialize, (ISizeFactory(address(sizeFactory))))
                )
            )
        );
        vm.startPrank(SAFE);
        sizeFactory.setRheoImplementation(address(rheoImpl));
        sizeFactory.setNonTransferrableRebasingTokenVaultImplementation(address(vaultImpl));
        sizeFactory.setCollectionsManager(cmProxy);
        vm.stopPrank();
    }

    function _phase2_CreateBorrowVaultAndAdapters() internal {
        vm.prank(SAFE);
        borrowTokenVault = NonTransferrableRebasingTokenVault(
            address(
                sizeFactory.createBorrowTokenVault(IPool(cfg.variablePool), IERC20Metadata(cfg.underlyingBorrowToken))
            )
        );
        aaveAdapter = new AaveAdapter(borrowTokenVault);
        erc4626Adapter = new ERC4626Adapter(borrowTokenVault);
        vm.startPrank(SAFE);
        borrowTokenVault.setAdapter(AAVE_ADAPTER_ID, aaveAdapter);
        borrowTokenVault.setVaultAdapter(DEFAULT_VAULT, AAVE_ADAPTER_ID);
        borrowTokenVault.setAdapter(ERC4626_ADAPTER_ID, erc4626Adapter);
        vm.stopPrank();
    }

    function _phase3_DeployPriceFeed() internal {
        priceFeed = new PriceFeed(cfg.priceFeedParams);
    }

    function _phase5_CreateMarket() internal {
        InitializeFeeConfigParams memory feeConfig = InitializeFeeConfigParams({
            swapFeeAPR: 0.005e18,
            fragmentationFee: cfg.fragmentationFee,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.001e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: FEE_RECIPIENT
        });
        uint256[] memory maturities = new uint256[](4);
        maturities[0] = 1782460800;
        maturities[1] = 1790323200;
        maturities[2] = 1798704000;
        maturities[3] = 1806048000;
        InitializeRiskConfigParams memory riskConfig = InitializeRiskConfigParams({
            crOpening: cfg.crOpening,
            crLiquidation: cfg.crLiquidation,
            minimumCreditBorrowToken: cfg.minimumCreditBorrowToken,
            minTenor: 1 hours,
            maxTenor: 5 * 365 days,
            maturities: maturities
        });
        InitializeOracleParams memory oracle = InitializeOracleParams({priceFeed: address(priceFeed)});
        InitializeDataParams memory data = InitializeDataParams({
            weth: cfg.weth,
            collateralAssets: singleCollateralAsset(cfg.underlyingCollateralToken, address(priceFeed)),
            underlyingBorrowToken: cfg.underlyingBorrowToken,
            variablePool: cfg.variablePool,
            borrowTokenVault: address(borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });
        vm.prank(SAFE);
        market = IRheo(sizeFactory.createMarketRheo(feeConfig, riskConfig, data));
    }

    function _phase7_DeployPauseAll() internal {
        pauseAll = new PauseAll(ISizeFactory(address(sizeFactory)), SAFE);
    }

    function _phase8_GrantPauserRole() internal {
        vm.prank(SAFE);
        AccessControlUpgradeable(address(sizeFactory)).grantRole(PAUSER_ROLE, address(pauseAll));
    }

    /// @dev Step 1 of the handoff. Safe initiates the transfer; ownership has NOT moved yet.
    function testFork_TransferOwnership_setsPendingButRetainsCurrentOwner() public {
        vm.prank(SAFE);
        pauseAll.transferOwnership(hypernativeBot);

        assertEq(pauseAll.owner(), SAFE, "owner unchanged until accept");
        assertEq(pauseAll.pendingOwner(), hypernativeBot, "bot is pending owner");
    }

    /// @dev While the transfer is pending, only the Safe can still pause.
    function testFork_TransferPending_safeStillOwner_botCannotPauseYet() public {
        vm.prank(SAFE);
        pauseAll.transferOwnership(hypernativeBot);

        vm.prank(hypernativeBot);
        vm.expectRevert();
        pauseAll.pauseAll();
    }

    /// @dev Step 2 of the handoff. Bot accepts → ownership flips → bot can pause.
    function testFork_AcceptOwnership_flipsControlAndEnablesPause() public {
        vm.prank(SAFE);
        pauseAll.transferOwnership(hypernativeBot);

        vm.prank(hypernativeBot);
        pauseAll.acceptOwnership();

        assertEq(pauseAll.owner(), hypernativeBot, "owner flipped to bot");
        assertEq(pauseAll.pendingOwner(), address(0), "pendingOwner cleared after accept");

        // Bot can now pause every market.
        vm.prank(hypernativeBot);
        pauseAll.pauseAll();
        assertTrue(PausableUpgradeable(address(market)).paused(), "market paused by bot");
    }

    /// @dev After handoff, the Safe is no longer the owner and can't pause via this contract.
    function testFork_AfterHandoff_safeLosesPauseAllAccess() public {
        vm.prank(SAFE);
        pauseAll.transferOwnership(hypernativeBot);
        vm.prank(hypernativeBot);
        pauseAll.acceptOwnership();

        vm.prank(SAFE);
        vm.expectRevert();
        pauseAll.pauseAll();
    }

    /// @dev Only the pending owner can accept — random callers (including the Safe) cannot.
    function testFork_AcceptOwnership_rejectsNonPendingOwner() public {
        vm.prank(SAFE);
        pauseAll.transferOwnership(hypernativeBot);

        vm.prank(SAFE);
        vm.expectRevert();
        pauseAll.acceptOwnership();

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        pauseAll.acceptOwnership();
    }

    /// @dev Handoff is reversible until accept: Safe can re-target the pending owner or cancel
    ///      by setting pendingOwner back to address(0) via transferOwnership.
    function testFork_TransferOwnership_canBeRetargetedBeforeAccept() public {
        vm.prank(SAFE);
        pauseAll.transferOwnership(hypernativeBot);

        address newBot = makeAddr("newHypernativeBot");
        vm.prank(SAFE);
        pauseAll.transferOwnership(newBot);

        assertEq(pauseAll.pendingOwner(), newBot, "pendingOwner re-targeted");

        vm.prank(hypernativeBot);
        vm.expectRevert();
        pauseAll.acceptOwnership(); // the original bot can no longer accept
    }
}
