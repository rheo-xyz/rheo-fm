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

/// @title ArbitrumPauseAllForkTest
/// @notice End-to-end dry run for Phases 7-8 — deploys PauseAll owned by the Safe, grants
///         `PAUSER_ROLE` on the SizeFactory to PauseAll, then proves the Safe can pause every
///         market with one call. Built on top of `ArbitrumLiveMarketDeploymentForkTest`'s setup
///         pattern so the test exercises the real live factory bytecode.
///
///         Run: `FOUNDRY_PROFILE=fork forge test --mc ArbitrumPauseAllForkTest -vvv`
contract ArbitrumPauseAllForkTest is Test, Networks {
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address private constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;

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

    function testFork_PauseAll_ownedBySafe() public view {
        assertEq(pauseAll.owner(), SAFE, "PauseAll should be Safe-owned");
    }

    function testFork_PauseAll_sizeFactoryWired() public view {
        assertEq(address(pauseAll.sizeFactory()), address(sizeFactory), "SizeFactory wired");
    }

    function testFork_PauseAll_hasPauserRoleOnFactory() public view {
        assertTrue(
            AccessControlUpgradeable(address(sizeFactory)).hasRole(PAUSER_ROLE, address(pauseAll)),
            "PauseAll should hold PAUSER_ROLE on the factory"
        );
    }

    function testFork_PauseAll_pausesEveryMarket() public {
        // Sanity: market is unpaused right after creation.
        assertFalse(PausableUpgradeable(address(market)).paused(), "market should start unpaused");

        vm.prank(SAFE);
        pauseAll.pauseAll();

        assertTrue(PausableUpgradeable(address(market)).paused(), "market should be paused after pauseAll()");
    }

    /// @dev Idempotent — calling pauseAll twice doesn't revert. The skip-already-paused branch
    ///      keeps a partial-failure scenario from rolling back the whole tx.
    function testFork_PauseAll_idempotent() public {
        vm.prank(SAFE);
        pauseAll.pauseAll();
        vm.prank(SAFE);
        pauseAll.pauseAll(); // no revert
        assertTrue(PausableUpgradeable(address(market)).paused(), "market still paused");
    }

    function testFork_PauseAll_revertsForNonOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        pauseAll.pauseAll();
    }

    /// @dev If the factory revokes PAUSER_ROLE from PauseAll (e.g. via Safe), subsequent calls
    ///      must fail loudly rather than silently no-op.
    function testFork_PauseAll_revertsWhenPauserRoleRevoked() public {
        vm.prank(SAFE);
        AccessControlUpgradeable(address(sizeFactory)).revokeRole(PAUSER_ROLE, address(pauseAll));

        vm.prank(SAFE);
        vm.expectRevert();
        pauseAll.pauseAll();
    }
}
