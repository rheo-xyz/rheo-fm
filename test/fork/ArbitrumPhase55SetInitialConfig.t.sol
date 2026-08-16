// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {singleCollateralAsset} from "@rheo-fm/script/CollateralAssets.sol";

import {IPool} from "@aave/interfaces/IPool.sol";
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
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

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

import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Test} from "forge-std/Test.sol";

/// @title ArbitrumPhase55SetInitialConfigForkTest
/// @notice Dry run for Phase 5.5 — proves the Safe-routed
///         `market.updateConfig("overdueLiquidationRewardPercent", 0.01e18)` call succeeds and
///         the new value lands in storage. Runs Phases 1.2 → 5 inline first (same pattern as
///         ArbitrumLiveMarketDeploymentForkTest) and then exercises the 5.5 update.
///
///         Run: `FOUNDRY_PROFILE=fork forge test --mc ArbitrumPhase55SetInitialConfigForkTest -vvv`
contract ArbitrumPhase55SetInitialConfigForkTest is Test, Networks {
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address private constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;

    /// State-storage slot for `state.data.overdueLiquidationRewardPercent`. Same constant the
    /// team's own test base (test/BaseTest.sol:75) uses to read this value via extSload; we use
    /// `vm.load` from the test side. If the Rheo storage layout ever changes this constant must
    /// be updated in lockstep.
    uint256 private constant OVERDUE_LIQUIDATION_REWARD_SLOT = 29;

    uint256 private constant OVERDUE_LIQUIDATION_REWARD_PERCENT = 0.01e18;

    SizeFactory private sizeFactory;
    NonTransferrableRebasingTokenVault private borrowTokenVault;
    AaveAdapter private aaveAdapter;
    ERC4626Adapter private erc4626Adapter;
    IPriceFeed private priceFeed;
    IRheo private market;
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

    /// @dev Confirms the post-init default before Phase 5.5 runs: the market should already have
    ///      `overdueLiquidationRewardPercent == liquidationRewardPercent == 0.05e18` (5 %).
    ///      If this assertion fails, either the storage layout has shifted or the init logic at
    ///      Initialize.sol:288 changed — either way Phase 5.5's assumed delta is invalid.
    function testFork_Phase55_postInitDefaultIsFivePercent() public view {
        uint256 stored = uint256(vm.load(address(market), bytes32(OVERDUE_LIQUIDATION_REWARD_SLOT)));
        assertEq(stored, 0.05e18, "init default should mirror liquidationRewardPercent (5%)");
    }

    /// @dev The actual Phase 5.5 ceremony: Safe pranks updateConfig, storage updates to 1 %.
    function testFork_Phase55_updateConfigLandsOnePercent() public {
        vm.prank(SAFE);
        market.updateConfig(
            UpdateConfigParams({key: "overdueLiquidationRewardPercent", value: OVERDUE_LIQUIDATION_REWARD_PERCENT})
        );

        uint256 stored = uint256(vm.load(address(market), bytes32(OVERDUE_LIQUIDATION_REWARD_SLOT)));
        assertEq(stored, OVERDUE_LIQUIDATION_REWARD_PERCENT, "post-Phase-5.5 should be 0.01e18 (1%)");
    }

    /// @dev A non-Safe caller can NOT do this update. Pin the access-control contract here.
    function testFork_Phase55_revertsForNonAdmin() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        market.updateConfig(
            UpdateConfigParams({key: "overdueLiquidationRewardPercent", value: OVERDUE_LIQUIDATION_REWARD_PERCENT})
        );
    }
}
