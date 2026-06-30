// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {LiquidateParams} from "@rheo-fm/src/market/libraries/actions/Liquidate.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

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

/// @title ArbitrumWethUsdcLifecycleForkTest
/// @notice F3 — the full deposit → buyCreditLimit → sellCreditMarket → price-drop → liquidate flow
///         against the live Arbitrum factory. All 17 prior assertions prove the market was *created*
///         with the right params; this test proves the market *works*.
///
///         Run: `FOUNDRY_PROFILE=fork forge test --mc ArbitrumWethUsdcLifecycleForkTest -vvv`
contract ArbitrumWethUsdcLifecycleForkTest is Test, Networks {
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address private constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;
    AggregatorV3Interface private constant ETH_USD_FEED =
        AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    SizeFactory private sizeFactory;
    NonTransferrableRebasingTokenVault private borrowTokenVault;
    IPriceFeed private priceFeed;
    IRheo private market;
    NetworkConfiguration private cfg;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private liquidator = makeAddr("liquidator");

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

    /// @notice Lifecycle: alice lends, bob borrows, ETH crashes 30%, liquidator closes bob's position.
    function testFork_ArbitrumLive_lifecycle_borrowThenLiquidate() public {
        // ─── Step 1: fund the actors with real Arbitrum tokens ──────────────────────────────────
        deal(cfg.underlyingBorrowToken, alice, 100_000e6); // 100k USDC for alice (lender)
        deal(cfg.underlyingCollateralToken, bob, 10e18); // 10 WETH for bob (borrower)
        // Liquidator needs USDC to repay bob's debt during the liquidation call.
        deal(cfg.underlyingBorrowToken, liquidator, 10_000e6);

        // ─── Step 2: alice deposits USDC into the market ────────────────────────────────────────
        vm.startPrank(alice);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 100_000e6);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 100_000e6, to: alice}));
        vm.stopPrank();

        // ─── Step 3: alice posts a buyCreditLimit (lending offer) at every active maturity ──────
        // Use the four maturities configured in the proposal script: Q2/Q3/Q4 2026 + Q1 2027.
        uint256[] memory maturities = new uint256[](4);
        maturities[0] = 1782460800;
        maturities[1] = 1790323200;
        maturities[2] = 1798704000;
        maturities[3] = 1806048000;

        uint256[] memory aprs = new uint256[](4);
        aprs[0] = 0.06e18; // 6 % APR
        aprs[1] = 0.07e18;
        aprs[2] = 0.08e18;
        aprs[3] = 0.09e18;

        // The test runs against a fork at "latest"; advance time so maturities are still in the
        // future (the live block timestamp may overshoot some of them once we reach Q2 2026).
        if (block.timestamp >= maturities[0] - 1 days) {
            vm.warp(maturities[0] - 30 days);
        }

        vm.prank(alice);
        market.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));

        // ─── Step 4: bob deposits WETH and borrows USDC against alice's nearest-maturity offer ──
        vm.startPrank(bob);
        IERC20(cfg.underlyingCollateralToken).approve(address(market), 10e18);
        market.deposit(DepositParams({token: cfg.underlyingCollateralToken, amount: 10e18, to: bob}));
        vm.stopPrank();

        uint256 debtPositionId = market.data().nextDebtPositionId;

        vm.prank(bob);
        market.sellCreditMarket(
            SellCreditMarketParams({
                lender: alice,
                creditPositionId: RESERVED_ID,
                amount: 5_000e6, // borrow 5k USDC
                maturity: maturities[0],
                deadline: block.timestamp + 1 hours,
                maxAPR: 0.10e18,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );

        // Sanity: the debt position now exists.
        assertEq(market.getDebtPosition(debtPositionId).borrower, bob, "debt position should be bob's");

        // ─── Step 5: ETH price crashes 85 % — mock the Chainlink ETH/USD aggregator ─────────────
        // A 30 % drop is insufficient to push the position below the 130 % crLiquidation threshold
        // because the position opened at ~600 % CR (10 WETH * $3 000 / 5 000 USDC). The bigger
        // drop ensures the liquidation path is exercised regardless of where the live price sits
        // at fork time.
        (, int256 livePrice,,,) = ETH_USD_FEED.latestRoundData();
        int256 crashedPrice = (livePrice * 15) / 100; // -85%
        vm.mockCall(
            address(ETH_USD_FEED),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), crashedPrice, block.timestamp, block.timestamp, uint80(1))
        );

        // ─── Step 6: liquidator deposits USDC + closes bob's position ────────────────────────────
        // Rheo's liquidation flow has the liquidator pay the debt in USDC and receive collateral
        // (szWETH) in return. The liquidator must hold borrow-token balance in the market — i.e.
        // they need to `deposit` USDC first.
        vm.startPrank(liquidator);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 10_000e6);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 10_000e6, to: liquidator}));
        uint256 liquidatorProfit = market.liquidate(
            LiquidateParams({debtPositionId: debtPositionId, minimumCollateralProfit: 0, deadline: block.timestamp + 1 hours})
        );
        vm.stopPrank();

        // Assert the liquidation actually fired.
        assertGt(liquidatorProfit, 0, "liquidator should receive a positive collateral profit");
        assertEq(
            market.getDebtPosition(debtPositionId).futureValue,
            0,
            "debt position futureValue should be 0 post-liquidation"
        );
    }

    // ─── Setup helpers (mirrored from ArbitrumLiveMarketDeploymentForkTest) ─────────────────────

    function _phase1_2_EnsureImplementationsWired() internal {
        Rheo rheoImpl = new Rheo();
        NonTransferrableRebasingTokenVault vaultImpl = new NonTransferrableRebasingTokenVault();
        CollectionsManager cmImpl = new CollectionsManager();
        CollectionsManager cmProxy = CollectionsManager(
            address(
                new ERC1967Proxy(address(cmImpl), abi.encodeCall(CollectionsManager.initialize, (ISizeFactory(address(sizeFactory)))))
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

        AaveAdapter aaveAdapter = new AaveAdapter(borrowTokenVault);
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(borrowTokenVault);

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

        InitializeDataParams memory dataParams = InitializeDataParams({
            weth: cfg.weth,
            underlyingCollateralToken: cfg.underlyingCollateralToken,
            underlyingBorrowToken: cfg.underlyingBorrowToken,
            variablePool: cfg.variablePool,
            borrowTokenVault: address(borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });

        vm.prank(SAFE);
        market = IRheo(sizeFactory.createMarketRheo(feeConfig, riskConfig, oracle, dataParams));
    }
}
