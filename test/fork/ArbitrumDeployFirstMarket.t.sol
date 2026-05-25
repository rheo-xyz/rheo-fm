// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

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
import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

/// @title ArbitrumDeployFirstMarketForkTest
/// @notice End-to-end dry run for the Arbitrum WETH/USDC market launch.
/// @dev Forks Arbitrum mainnet, runs Phases 1-3 + 5 from the deployment plan against
///      real Aave / Chainlink / WETH / USDC, and asserts the resulting market matches
///      what `script/ProposeSafeTxDeployFirstMarketArbitrum.s.sol` will propose.
///      Run with: FOUNDRY_PROFILE=fork forge test --mc ArbitrumDeployFirstMarketForkTest -vvv
contract ArbitrumDeployFirstMarketForkTest is Test, Networks {
    /// Mirrors the constant in ProposeSafeTxDeployFirstMarketArbitrum.s.sol
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address private constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;

    ISizeFactory private sizeFactory;
    CollectionsManager private collectionsManager;
    IPriceFeed private priceFeed;
    NonTransferrableRebasingTokenVault private borrowTokenVault;
    IRheo private market;
    NetworkConfiguration private cfg;

    function setUp() public {
        // Prefer Alchemy-keyed Arbitrum RPC if API_KEY_ALCHEMY is set, fall back to the public archive node.
        try vm.envString("API_KEY_ALCHEMY") returns (string memory) {
            vm.createSelectFork("arbitrum-production");
        } catch {
            vm.createSelectFork("arbitrum_archive");
        }
        cfg = params("arbitrum-production-weth-usdc");

        _phase1_DeployFactoryStack();
        _phase2_CreateBorrowTokenVault();
        _phase3_DeployPriceFeed();
        _phase5_CreateMarket();
    }

    function _phase1_DeployFactoryStack() internal {
        // SizeFactory proxy + impl, owner = SAFE
        SizeFactory factoryImpl = new SizeFactory();
        sizeFactory = ISizeFactory(
            address(new ERC1967Proxy(address(factoryImpl), abi.encodeCall(SizeFactory.initialize, (SAFE))))
        );

        // CollectionsManager proxy + impl
        CollectionsManager cmImpl = new CollectionsManager();
        collectionsManager = CollectionsManager(
            address(new ERC1967Proxy(address(cmImpl), abi.encodeCall(CollectionsManager.initialize, (sizeFactory))))
        );

        // Wire CollectionsManager and implementations onto factory (Safe-owned ops)
        vm.startPrank(SAFE);
        SizeFactory(payable(address(sizeFactory))).setCollectionsManager(collectionsManager);
        sizeFactory.setNonTransferrableRebasingTokenVaultImplementation(address(new NonTransferrableRebasingTokenVault()));
        sizeFactory.setRheoImplementation(address(new Rheo()));
        vm.stopPrank();
    }

    function _phase2_CreateBorrowTokenVault() internal {
        vm.startPrank(SAFE);
        // Cast through `address` because SizeFactory returns the rheo-solidity flavor of the vault type,
        // while the rest of this test (and the production market) wires the rheo-fm flavor — same
        // bytecode, distinct Solidity types. Mirrors script/Deploy.sol#162.
        borrowTokenVault = NonTransferrableRebasingTokenVault(
            address(
                sizeFactory.createBorrowTokenVault(IPool(cfg.variablePool), IERC20Metadata(cfg.underlyingBorrowToken))
            )
        );

        AaveAdapter aaveAdapter = new AaveAdapter(borrowTokenVault);
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(borrowTokenVault);

        borrowTokenVault.setAdapter(AAVE_ADAPTER_ID, aaveAdapter);
        borrowTokenVault.setVaultAdapter(DEFAULT_VAULT, AAVE_ADAPTER_ID);
        borrowTokenVault.setAdapter(ERC4626_ADAPTER_ID, erc4626Adapter);
        vm.stopPrank();
    }

    function _phase3_DeployPriceFeed() internal {
        priceFeed = IPriceFeed(address(new PriceFeed(cfg.priceFeedParams)));
    }

    function _phase5_CreateMarket() internal {
        InitializeFeeConfigParams memory feeConfigParams = InitializeFeeConfigParams({
            swapFeeAPR: 0.005e18,
            fragmentationFee: cfg.fragmentationFee,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.001e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: FEE_RECIPIENT
        });

        uint256[] memory maturities = new uint256[](4);
        maturities[0] = 1782460800; // 2026-06-26 08:00 UTC (Q2 2026)
        maturities[1] = 1790323200; // 2026-09-25 08:00 UTC (Q3 2026)
        maturities[2] = 1798704000; // 2026-12-31 08:00 UTC (Q4 2026)
        maturities[3] = 1806048000; // 2027-03-26 08:00 UTC (Q1 2027)

        InitializeRiskConfigParams memory riskConfigParams = InitializeRiskConfigParams({
            crOpening: cfg.crOpening,
            crLiquidation: cfg.crLiquidation,
            minimumCreditBorrowToken: cfg.minimumCreditBorrowToken,
            minTenor: 1 hours,
            maxTenor: 5 * 365 days,
            maturities: maturities
        });

        InitializeOracleParams memory oracleParams = InitializeOracleParams({priceFeed: address(priceFeed)});

        InitializeDataParams memory dataParams = InitializeDataParams({
            weth: cfg.weth,
            underlyingCollateralToken: cfg.underlyingCollateralToken,
            underlyingBorrowToken: cfg.underlyingBorrowToken,
            variablePool: cfg.variablePool,
            borrowTokenVault: address(borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });

        vm.prank(SAFE);
        market =
            IRheo(sizeFactory.createMarketRheo(feeConfigParams, riskConfigParams, oracleParams, dataParams));
    }

    function testFork_ArbitrumDeployFirstMarket_priceFeedReturnsSaneEthUsdcPrice() public view {
        uint256 price = priceFeed.getPrice();
        assertGt(price, 1_000e18, "ETH/USDC price below sane floor");
        assertLt(price, 100_000e18, "ETH/USDC price above sane ceiling");
        assertEq(priceFeed.decimals(), 18, "PriceFeed must report 18 decimals");
    }

    function testFork_ArbitrumDeployFirstMarket_marketDataMatchesArbitrumConfig() public view {
        DataView memory d = market.data();
        assertEq(address(d.underlyingCollateralToken), cfg.underlyingCollateralToken, "collateral token");
        assertEq(address(d.underlyingBorrowToken), cfg.underlyingBorrowToken, "borrow token");
        assertEq(address(d.variablePool), cfg.variablePool, "variable pool");
        assertEq(address(d.borrowTokenVault), address(borrowTokenVault), "borrow token vault");
    }

    function testFork_ArbitrumDeployFirstMarket_oracleIsWired() public view {
        assertEq(market.oracle().priceFeed, address(priceFeed), "oracle priceFeed");
    }

    function testFork_ArbitrumDeployFirstMarket_riskConfigMatchesProposal() public view {
        InitializeRiskConfigParams memory r = market.riskConfig();
        assertEq(r.crOpening, cfg.crOpening, "crOpening");
        assertEq(r.crLiquidation, cfg.crLiquidation, "crLiquidation");
        assertEq(r.minimumCreditBorrowToken, cfg.minimumCreditBorrowToken, "minimumCreditBorrowToken");
        assertEq(r.minTenor, 1 hours, "minTenor");
        assertEq(r.maxTenor, 5 * 365 days, "maxTenor");
        assertEq(r.maturities.length, 4, "maturities length");
        assertEq(r.maturities[0], 1782460800, "maturity Q2 2026");
        assertEq(r.maturities[1], 1790323200, "maturity Q3 2026");
        assertEq(r.maturities[2], 1798704000, "maturity Q4 2026");
        assertEq(r.maturities[3], 1806048000, "maturity Q1 2027");
    }

    function testFork_ArbitrumDeployFirstMarket_feeConfigMatchesProposal() public view {
        InitializeFeeConfigParams memory f = market.feeConfig();
        assertEq(f.swapFeeAPR, 0.005e18, "swapFeeAPR");
        assertEq(f.fragmentationFee, cfg.fragmentationFee, "fragmentationFee");
        assertEq(f.liquidationRewardPercent, 0.05e18, "liquidationRewardPercent");
        assertEq(f.overdueCollateralProtocolPercent, 0.001e18, "overdueCollateralProtocolPercent");
        assertEq(f.collateralProtocolPercent, 0.1e18, "collateralProtocolPercent");
        assertEq(f.feeRecipient, FEE_RECIPIENT, "feeRecipient");
    }

    function testFork_ArbitrumDeployFirstMarket_marketIsRegisteredOnFactory() public view {
        assertEq(sizeFactory.getMarket(0), address(market), "market should be index 0");
        assertEq(sizeFactory.getMarketsCount(), 1, "factory should hold exactly one market");
    }

    /// @dev F11 — wiring assertions on every PriceFeed sub-contract. A passing `getPrice()` sanity
    ///      check doesn't tell you the wiring is right.
    function testFork_ArbitrumDeployFirstMarket_priceFeedSubContractsCorrectlyWired() public view {
        PriceFeed pf = PriceFeed(address(priceFeed));

        assertEq(
            address(pf.chainlinkSequencerUptimeFeed().sequencerUptimeFeed()),
            0xFdB631F5EE196F0ed6FAa767959853A9F217697D,
            "sequencer feed wiring"
        );
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
        assertEq(
            address(pf.uniswapV3PriceFeed().uniswapV3Pool()),
            0xC6962004f452bE9203591991D15f6b388e09E8D0,
            "Uniswap V3 pool"
        );
        assertEq(pf.uniswapV3PriceFeed().twapWindow(), 15 minutes, "TWAP window");
        assertEq(pf.uniswapV3PriceFeed().averageBlockTime(), 1, "average block time");
    }
}
