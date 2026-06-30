// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
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

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";

import {Test} from "forge-std/Test.sol";

/// @title ArbitrumLiveMarketDeploymentForkTest
/// @notice End-to-end dry run for the Arbitrum WETH/USDC launch against the **live** SizeFactory
///         deployed at the address in `Networks.sol`. Phase 1.2 wiring is performed inline (the
///         test self-heals if the live factory hasn't been wired yet — it sets fresh impls via a
///         Safe prank), then Phase 2 (vault + adapters), Phase 3 (price feed), and Phase 5 (market)
///         run in sequence. Final assertions match `ArbitrumDeployFirstMarketForkTest`.
///
///         Run: FOUNDRY_PROFILE=fork forge test --mc ArbitrumLiveMarketDeploymentForkTest -vvv
contract ArbitrumLiveMarketDeploymentForkTest is Test, Networks {
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address private constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;

    SizeFactory private sizeFactory;
    CollectionsManager private collectionsManager;
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

        _phase1_2_EnsureImplementationsWired();
        _phase2_CreateBorrowVaultAndAdapters();
        _phase3_DeployPriceFeed();
        _phase5_CreateMarket();
    }

    /// @dev Deploys fresh impls + CM and wires them onto the live factory. Overwrites any existing
    ///      wiring in the fork — fine for test purposes, the prior wiring would point at impls
    ///      with identical bytecode.
    function _phase1_2_EnsureImplementationsWired() internal {
        Rheo rheoImpl = new Rheo();
        NonTransferrableRebasingTokenVault vaultImpl = new NonTransferrableRebasingTokenVault();
        CollectionsManager cmImpl = new CollectionsManager();
        collectionsManager = CollectionsManager(
            address(
                new ERC1967Proxy(address(cmImpl), abi.encodeCall(CollectionsManager.initialize, (ISizeFactory(address(sizeFactory)))))
            )
        );

        vm.startPrank(SAFE);
        sizeFactory.setRheoImplementation(address(rheoImpl));
        sizeFactory.setNonTransferrableRebasingTokenVaultImplementation(address(vaultImpl));
        sizeFactory.setCollectionsManager(collectionsManager);
        vm.stopPrank();
    }

    function _phase2_CreateBorrowVaultAndAdapters() internal {
        // Phase 2a: Safe creates the vault
        vm.prank(SAFE);
        borrowTokenVault = NonTransferrableRebasingTokenVault(
            address(
                sizeFactory.createBorrowTokenVault(IPool(cfg.variablePool), IERC20Metadata(cfg.underlyingBorrowToken))
            )
        );

        // Phase 2b: EOA deploys adapters
        aaveAdapter = new AaveAdapter(borrowTokenVault);
        erc4626Adapter = new ERC4626Adapter(borrowTokenVault);

        // Phase 2c: Safe wires adapters on the vault (matches the batched setters in the proposal script)
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
            underlyingCollateralToken: cfg.underlyingCollateralToken,
            underlyingBorrowToken: cfg.underlyingBorrowToken,
            variablePool: cfg.variablePool,
            borrowTokenVault: address(borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });

        vm.prank(SAFE);
        market = IRheo(sizeFactory.createMarketRheo(feeConfig, riskConfig, oracle, data));
    }

    function testFork_ArbitrumLive_marketIsRegisteredOnFactory() public view {
        // Could be index > 0 if another test deployed a market first; assert via isMarket instead.
        assertTrue(sizeFactory.isRheoMarket(address(market)), "market not registered on live factory");
    }

    function testFork_ArbitrumLive_priceFeedReturnsSaneEthUsdcPrice() public view {
        uint256 price = priceFeed.getPrice();
        // 18-decimal ETH/USDC: expect something in (1_000, 100_000) e18
        assertGt(price, 1_000e18, "price too low");
        assertLt(price, 100_000e18, "price too high");
    }

    function testFork_ArbitrumLive_marketDataMatchesArbitrumConfig() public view {
        DataView memory d = market.data();
        assertEq(address(d.underlyingCollateralToken), cfg.underlyingCollateralToken, "collateral");
        assertEq(address(d.underlyingBorrowToken), cfg.underlyingBorrowToken, "borrow");
        assertEq(address(d.variablePool), cfg.variablePool, "variable pool");
        assertEq(address(d.borrowTokenVault), address(borrowTokenVault), "borrow vault");
    }

    function testFork_ArbitrumLive_oracleIsWired() public view {
        assertEq(market.oracle().priceFeed, address(priceFeed), "oracle priceFeed");
    }

    function testFork_ArbitrumLive_riskConfigMatchesProposal() public view {
        InitializeRiskConfigParams memory r = market.riskConfig();
        assertEq(r.crOpening, 1.5e18, "crOpening");
        assertEq(r.crLiquidation, 1.3e18, "crLiquidation");
        assertEq(r.minimumCreditBorrowToken, 10e6, "minimumCreditBorrowToken");
        assertEq(r.minTenor, 1 hours, "minTenor");
        assertEq(r.maxTenor, 5 * 365 days, "maxTenor");
        assertEq(r.maturities.length, 4, "maturities length");
        assertEq(r.maturities[0], 1782460800, "maturity Q2 2026");
        assertEq(r.maturities[1], 1790323200, "maturity Q3 2026");
        assertEq(r.maturities[2], 1798704000, "maturity Q4 2026");
        assertEq(r.maturities[3], 1806048000, "maturity Q1 2027");
    }

    function testFork_ArbitrumLive_feeConfigMatchesProposal() public view {
        InitializeFeeConfigParams memory f = market.feeConfig();
        assertEq(f.swapFeeAPR, 0.005e18, "swapFeeAPR");
        assertEq(f.fragmentationFee, 1e6, "fragmentationFee");
        assertEq(f.liquidationRewardPercent, 0.05e18, "liquidationRewardPercent");
        assertEq(f.overdueCollateralProtocolPercent, 0.001e18, "overdueCollateralProtocolPercent");
        assertEq(f.collateralProtocolPercent, 0.1e18, "collateralProtocolPercent");
        assertEq(f.feeRecipient, FEE_RECIPIENT, "feeRecipient");
    }

    function testFork_ArbitrumLive_defaultVaultAdapterIsAave() public view {
        // ERC4626_ADAPTER_ID is also registered but the only public way to assert that is to
        // attach a real ERC4626 vault first — out of scope here. Default-vault assertion is
        // enough to prove the wiring tx ran and set the right adapter.
        assertEq(
            address(borrowTokenVault.getWhitelistedVaultAdapter(DEFAULT_VAULT)),
            address(aaveAdapter),
            "default vault adapter should be Aave"
        );
    }

    /// @dev F11 — wiring assertions on every PriceFeed sub-contract. A passing `getPrice()` sanity
    ///      check doesn't tell you the wiring is right (Chainlink could be wrong and Uniswap could
    ///      coincidentally produce a similar price). Pin every immutable.
    function testFork_ArbitrumLive_priceFeedSubContractsCorrectlyWired() public view {
        PriceFeed pf = PriceFeed(address(priceFeed));

        // Sequencer guard wiring
        assertEq(
            address(pf.chainlinkSequencerUptimeFeed().sequencerUptimeFeed()),
            0xFdB631F5EE196F0ed6FAa767959853A9F217697D,
            "sequencer feed wiring"
        );

        // Chainlink primary wiring
        assertEq(
            address(pf.chainlinkPriceFeed().baseAggregator()),
            0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,
            "ETH/USD base aggregator"
        );
        assertEq(
            address(pf.chainlinkPriceFeed().quoteAggregator()),
            0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,
            "USDC/USD quote aggregator"
        );
        assertEq(pf.chainlinkPriceFeed().baseStalePriceInterval(), 95040, "base stale interval");
        assertEq(pf.chainlinkPriceFeed().quoteStalePriceInterval(), 95040, "quote stale interval");

        // Uniswap fallback wiring
        assertEq(
            address(pf.uniswapV3PriceFeed().uniswapV3Pool()),
            0xC6962004f452bE9203591991D15f6b388e09E8D0,
            "Uniswap V3 pool"
        );
        assertEq(pf.uniswapV3PriceFeed().twapWindow(), 15 minutes, "TWAP window");
        assertEq(pf.uniswapV3PriceFeed().averageBlockTime(), 1, "average block time");
    }
}
