// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// ─────────────────────────────────────────────────────────────────────────────────────────────
// ArbitrumLiveDeploymentAudit — Phase 2 (dynamic) of the deployment audit.
//
// Unlike the existing test/fork/Arbitrum*.t.sol fixtures (which deploy FRESH impls + create their
// OWN market on the live factory), every test here targets the **LIVE** market resolved via
// sizeFactory.getMarket(0) and the **LIVE** PriceFeed/PauseAll deployed on Arbitrum One. The point
// is to validate the actual on-chain deployment, not a freshly-minted in-test copy.
//
// Pinned to block 476895621 so results are reproducible against the Phase 1 cast evidence.
//   Run: FOUNDRY_PROFILE=fork forge test --mc ArbitrumLive -vv
// ─────────────────────────────────────────────────────────────────────────────────────────────

import {IPool} from "@aave/interfaces/IPool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {
    InitializeFeeConfigParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {LiquidateParams} from "@rheo-fm/src/market/libraries/actions/Liquidate.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {DEFAULT_VAULT, NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {IAdapter} from "@rheo-fm/src/market/token/adapters/IAdapter.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";
import {PauseAll} from "@rheo-fm/src/protection/PauseAll.sol";

import {ISizeFactory, PAUSER_ROLE} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";

import {Test} from "forge-std/Test.sol";

interface IUniswapV3PoolSlot0 {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

/// @dev Shared base: pins the fork and resolves all LIVE addresses from on-chain state.
abstract contract ArbitrumLiveForkBase is Test, Networks {
    uint256 internal constant PINNED_BLOCK = 476895621;

    address internal constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;
    address internal constant FEE_RECIPIENT = 0x12328eA44AB6D7B18aa9Cc030714763734b625dB;
    address internal constant PAUSE_ALL = 0xC16D1399B75bCC7aC6744491f4A596a7bd648C77;
    address internal constant PAUSE_ALL_OWNER_BOT = 0xa9Aa2d48847eC0Cac8D1c7168533077cfE2db47f;
    address internal constant UNI_POOL = 0xC6962004f452bE9203591991D15f6b388e09E8D0;
    address internal constant AAVE_ADAPTER = 0x10eE425c9df09fc7De3d6B363f37e0A3BB4e4E2d;

    AggregatorV3Interface internal constant ETH_USD_FEED =
        AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    AggregatorV3Interface internal constant USDC_USD_FEED =
        AggregatorV3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
    AggregatorV3Interface internal constant SEQUENCER_FEED =
        AggregatorV3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    // debtTokenCap = State slot 28, overdueLiquidationRewardPercent = State slot 29 (see RheoStorage.Data)
    uint256 internal constant SLOT_DEBT_TOKEN_CAP = 28;
    uint256 internal constant SLOT_OVERDUE_LIQ_REWARD = 29;

    SizeFactory internal sizeFactory;
    IRheo internal market;
    IPriceFeed internal priceFeed;
    NonTransferrableRebasingTokenVault internal borrowTokenVault;
    NetworkConfiguration internal cfg;

    function setUp() public virtual {
        vm.createSelectFork("arbitrum-production", PINNED_BLOCK);
        cfg = params("arbitrum-production-weth-usdc");

        sizeFactory = SizeFactory(payable(contracts[ARBITRUM_MAINNET][Contract.RHEO_FACTORY]));
        require(address(sizeFactory).code.length > 0, "live SizeFactory missing");

        require(sizeFactory.getMarketsCount() == 1, "expected exactly one live market");
        market = IRheo(sizeFactory.getMarket(0));
        require(address(market).code.length > 0, "live market missing");

        priceFeed = IPriceFeed(market.oracle().priceFeed);
        borrowTokenVault = NonTransferrableRebasingTokenVault(address(market.data().borrowTokenVault));
    }

    /// @dev Mirror the original lifecycle fixture's maturity-timing guard.
    function _activeMaturity() internal returns (uint256) {
        uint256[] memory mats = market.riskConfig().maturities;
        if (block.timestamp >= mats[0] - 1 days) {
            vm.warp(mats[0] - 30 days);
        }
        return mats[0];
    }
}

// ── 2.1 — LIVE market shape matches the intended deployment ────────────────────────────────────
contract ArbitrumLiveMarketStateForkTest is ArbitrumLiveForkBase {
    function testFork_Live_marketRegisteredAndSingleton() public view {
        assertEq(sizeFactory.getMarketsCount(), 1, "exactly one market");
        assertTrue(sizeFactory.isRheoMarket(address(market)), "market registered on live factory");
    }

    function testFork_Live_oracleIsLivePriceFeed() public view {
        assertEq(market.oracle().priceFeed, 0xB42d5e601276BB710085d953075576162cea7F70, "oracle is live PriceFeed");
        assertEq(address(priceFeed), 0xB42d5e601276BB710085d953075576162cea7F70, "priceFeed addr");
    }

    function testFork_Live_dataMatchesConfig() public view {
        DataView memory d = market.data();
        assertEq(address(d.underlyingCollateralToken), cfg.underlyingCollateralToken, "collateral=WETH");
        assertEq(address(d.underlyingBorrowToken), cfg.underlyingBorrowToken, "borrow=USDC");
        assertEq(address(d.variablePool), cfg.variablePool, "variablePool=Aave");
        assertEq(address(d.borrowTokenVault), 0x8AC402918518eEaC1c22EA5f49dcea6Ab2f84F2A, "borrowVault=svUSDC");
    }

    function testFork_Live_riskConfigMatchesIntent() public view {
        InitializeRiskConfigParams memory r = market.riskConfig();
        assertEq(r.crOpening, 1.5e18, "crOpening");
        assertEq(r.crLiquidation, 1.3e18, "crLiquidation");
        assertEq(r.minimumCreditBorrowToken, 10e6, "minCredit");
        assertEq(r.minTenor, 1 hours, "minTenor");
        assertEq(r.maxTenor, 5 * 365 days, "maxTenor");
        assertEq(r.maturities.length, 4, "4 maturities");
        assertEq(r.maturities[0], 1782460800, "Q2-2026");
        assertEq(r.maturities[1], 1790323200, "Q3-2026");
        assertEq(r.maturities[2], 1798704000, "Q4-2026");
        assertEq(r.maturities[3], 1806048000, "Q1-2027");
    }

    function testFork_Live_feeConfigMatchesIntent() public view {
        InitializeFeeConfigParams memory f = market.feeConfig();
        assertEq(f.swapFeeAPR, 0.005e18, "swapFeeAPR");
        assertEq(f.fragmentationFee, 1e6, "fragmentationFee");
        assertEq(f.liquidationRewardPercent, 0.05e18, "liqReward");
        assertEq(f.overdueCollateralProtocolPercent, 0.001e18, "overdueCollProto");
        assertEq(f.collateralProtocolPercent, 0.1e18, "collProto");
        assertEq(f.feeRecipient, FEE_RECIPIENT, "feeRecipient");
    }

    /// @dev The two post-init storage fields with no public getter.
    function testFork_Live_storageFields_overdueOnePercent_capUncapped() public view {
        uint256 overdue = uint256(vm.load(address(market), bytes32(SLOT_OVERDUE_LIQ_REWARD)));
        uint256 cap = uint256(vm.load(address(market), bytes32(SLOT_DEBT_TOKEN_CAP)));
        assertEq(overdue, 0.01e18, "overdueLiquidationRewardPercent should be 1% (Phase 5.5)");
        assertEq(cap, type(uint256).max, "debtTokenCap is UNCAPPED on-chain (5M cap never set)");
    }
}

// ── 2.2 / 2.3 — LIVE oracle: no-mock vs Chainlink, and sequencer-down revert ───────────────────
contract ArbitrumLiveOracleForkTest is ArbitrumLiveForkBase {
    /// 2.2 — no mocks: the wrapper price must equal ETH/USD ÷ USDC/USD within rounding.
    function testFork_Live_getPriceMatchesChainlink_noMock() public view {
        uint256 wrapped = priceFeed.getPrice(); // 18 decimals
        (, int256 ethUsd,,,) = ETH_USD_FEED.latestRoundData(); // 8 decimals
        (, int256 usdcUsd,,,) = USDC_USD_FEED.latestRoundData(); // 8 decimals
        assertGt(ethUsd, 0, "eth/usd > 0");
        assertGt(usdcUsd, 0, "usdc/usd > 0");
        uint256 expected = (uint256(ethUsd) * 1e18) / uint256(usdcUsd); // 18-decimal ETH/USDC
        // Allow 0.5% tolerance for any internal scaling/rounding in the wrapper.
        assertApproxEqRel(wrapped, expected, 0.005e18, "wrapper diverges from Chainlink primary");
    }

    /// 2.3 — mock the LIVE sequencer feed down; getPrice() on the LIVE PriceFeed must revert.
    function testFork_Live_sequencerDown_reverts() public {
        vm.mockCall(
            address(SEQUENCER_FEED),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1), block.timestamp - 1 days, block.timestamp, uint80(1))
        );
        vm.expectRevert(Errors.SEQUENCER_DOWN.selector);
        priceFeed.getPrice();
    }

    function testFork_Live_sequencerGracePeriod_reverts() public {
        vm.mockCall(
            address(SEQUENCER_FEED),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), block.timestamp - 1800, block.timestamp, uint80(1))
        );
        vm.expectRevert(Errors.GRACE_PERIOD_NOT_OVER.selector);
        priceFeed.getPrice();
    }
}

// ── 2.8 — Uniswap fallback observation cardinality (ops note) ──────────────────────────────────
contract ArbitrumLiveUniswapCardinalityForkTest is ArbitrumLiveForkBase {
    function testFork_Live_uniswapObservationCardinality() public {
        (,,, uint16 cardinality, uint16 cardinalityNext,,) = IUniswapV3PoolSlot0(UNI_POOL).slot0();
        emit log_named_uint("observationCardinality", cardinality);
        emit log_named_uint("observationCardinalityNext", cardinalityNext);
        // Threshold ≈ ceil(900/1) * 1.3 = 1170. Not an assertion-failure; just surface the value.
        if (cardinality < 1170) {
            emit log("NOTE: cardinality below ~1170 - full 15-min TWAP not yet queryable");
        }
    }
}

// ── 2.4 / 2.7 / 2.9 — LIVE market lifecycle, cap behavior, adapter→Aave flow ────────────────────
contract ArbitrumLiveLifecycleForkTest is ArbitrumLiveForkBase {
    address private alice = makeAddr("alice_live");
    address private bob = makeAddr("bob_live");
    address private liquidator = makeAddr("liquidator_live");

    /// 2.4 — full deposit → lend → borrow → 85% crash → liquidate against the LIVE market.
    function testFork_Live_lifecycle_borrowThenLiquidate() public {
        deal(cfg.underlyingBorrowToken, alice, 100_000e6);
        deal(cfg.underlyingCollateralToken, bob, 10e18);
        deal(cfg.underlyingBorrowToken, liquidator, 10_000e6);

        uint256 maturity = _activeMaturity();

        // alice lends
        vm.startPrank(alice);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 100_000e6);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 100_000e6, to: alice}));
        uint256[] memory mats = new uint256[](1);
        mats[0] = maturity;
        uint256[] memory aprs = new uint256[](1);
        aprs[0] = 0.06e18;
        market.buyCreditLimit(BuyCreditLimitParams({maturities: mats, aprs: aprs}));
        vm.stopPrank();

        // bob borrows 5k USDC against 10 WETH
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
                amount: 5_000e6,
                maturity: maturity,
                deadline: block.timestamp + 1 hours,
                maxAPR: 0.10e18,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        assertEq(market.getDebtPosition(debtPositionId).borrower, bob, "bob is borrower");

        // crash ETH 85%
        (, int256 livePrice,,,) = ETH_USD_FEED.latestRoundData();
        vm.mockCall(
            address(ETH_USD_FEED),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), (livePrice * 15) / 100, block.timestamp, block.timestamp, uint80(1))
        );

        // liquidator closes
        vm.startPrank(liquidator);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 10_000e6);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 10_000e6, to: liquidator}));
        uint256 profit = market.liquidate(
            LiquidateParams({debtPositionId: debtPositionId, minimumCollateralProfit: 0, deadline: block.timestamp + 1 hours})
        );
        vm.stopPrank();

        assertGt(profit, 0, "liquidator collateral profit > 0");
        assertEq(market.getDebtPosition(debtPositionId).futureValue, 0, "futureValue 0 post-liquidation");
    }

    /// 2.9 — a deposit must actually reach Aave: the Aave adapter's tracked balance for the
    ///       default vault increases by ~the deposited amount.
    function testFork_Live_depositReachesAave() public {
        IAdapter adapter = IAdapter(address(borrowTokenVault.getWhitelistedVaultAdapter(DEFAULT_VAULT)));
        assertEq(address(adapter), AAVE_ADAPTER, "default adapter is Aave");

        uint256 aaveBefore = adapter.totalSupply(DEFAULT_VAULT);

        deal(cfg.underlyingBorrowToken, alice, 50_000e6);
        vm.startPrank(alice);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 50_000e6);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 50_000e6, to: alice}));
        vm.stopPrank();

        uint256 aaveAfter = adapter.totalSupply(DEFAULT_VAULT);
        // Aave aToken ray-math rounds down by up to 1 wei; tolerate it.
        assertApproxEqAbs(borrowTokenVault.balanceOf(alice), 50_000e6, 2, "vault credits alice");
        assertApproxEqAbs(aaveAfter - aaveBefore, 50_000e6, 2, "USDC supplied to Aave via adapter");
    }

    /// 2.7 — debtTokenCap is uncapped on-chain: prove a >5M USDC debt position opens cleanly.
    function testFork_Live_uncapped_largeBorrowSucceeds() public {
        // confirm the cap slot first
        assertEq(uint256(vm.load(address(market), bytes32(SLOT_DEBT_TOKEN_CAP))), type(uint256).max, "cap is max");

        uint256 maturity = _activeMaturity();
        deal(cfg.underlyingBorrowToken, alice, 7_000_000e6); // lender
        deal(cfg.underlyingCollateralToken, bob, 10_000e18); // borrower (huge WETH collateral)

        vm.startPrank(alice);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 7_000_000e6);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 7_000_000e6, to: alice}));
        uint256[] memory mats = new uint256[](1);
        mats[0] = maturity;
        uint256[] memory aprs = new uint256[](1);
        aprs[0] = 0.06e18;
        market.buyCreditLimit(BuyCreditLimitParams({maturities: mats, aprs: aprs}));
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(cfg.underlyingCollateralToken).approve(address(market), 10_000e18);
        market.deposit(DepositParams({token: cfg.underlyingCollateralToken, amount: 10_000e18, to: bob}));
        // borrow 6M USDC (> 5M intended cap) — must NOT revert with DEBT_TOKEN_CAP_EXCEEDED
        market.sellCreditMarket(
            SellCreditMarketParams({
                lender: alice,
                creditPositionId: RESERVED_ID,
                amount: 6_000_000e6,
                maturity: maturity,
                deadline: block.timestamp + 1 hours,
                maxAPR: 0.10e18,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        vm.stopPrank();

        uint256 debtSupply = IERC20(address(market.data().debtToken)).totalSupply();
        assertGt(debtSupply, 5_000_000e6, "debt exceeds 5M (no cap enforced)");
    }
}

// ── 2.5 / 2.6 — LIVE PauseAll: pause/unpause E2E + ownership handoff state ──────────────────────
contract ArbitrumLivePauseAllForkTest is ArbitrumLiveForkBase {
    PauseAll private pauseAllLive;
    address private user = makeAddr("user_live");

    function setUp() public override {
        super.setUp();
        pauseAllLive = PauseAll(PAUSE_ALL);
    }

    /// 2.6 — ownership reflects a completed two-step handoff to the Hypernative bot.
    function testFork_Live_pauseAll_ownershipState() public view {
        assertEq(pauseAllLive.owner(), PAUSE_ALL_OWNER_BOT, "owner = Hypernative bot");
        assertEq(pauseAllLive.pendingOwner(), address(0), "no dangling pendingOwner");
        assertEq(address(pauseAllLive.sizeFactory()), address(sizeFactory), "sizeFactory wired");
        assertTrue(
            AccessControlUpgradeable(address(sizeFactory)).hasRole(PAUSER_ROLE, PAUSE_ALL),
            "PauseAll holds PAUSER_ROLE on factory"
        );
    }

    /// 2.5 — current owner pauses every market; deposits revert; Safe unpauses; idempotent.
    function testFork_Live_pauseAll_e2e() public {
        assertFalse(PausableUpgradeable(address(market)).paused(), "market starts unpaused");

        // (a) pauseAll by current owner (bot)
        vm.prank(PAUSE_ALL_OWNER_BOT);
        pauseAllLive.pauseAll();
        assertTrue(PausableUpgradeable(address(market)).paused(), "market paused after pauseAll");

        // (b) deposit reverts with EnforcedPause
        deal(cfg.underlyingBorrowToken, user, 1_000e6);
        vm.startPrank(user);
        IERC20(cfg.underlyingBorrowToken).approve(address(market), 1_000e6);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 1_000e6, to: user}));
        vm.stopPrank();

        // (c) Safe (DEFAULT_ADMIN + PAUSER via factory) unpauses → access restored
        vm.prank(SAFE);
        market.unpause();
        assertFalse(PausableUpgradeable(address(market)).paused(), "market unpaused by Safe");
        vm.startPrank(user);
        market.deposit(DepositParams({token: cfg.underlyingBorrowToken, amount: 1_000e6, to: user}));
        vm.stopPrank();
        // Aave aToken ray-math rounds down by up to 1 wei; tolerate it.
        assertApproxEqAbs(borrowTokenVault.balanceOf(user), 1_000e6, 2, "deposit works after unpause");

        // (d) idempotent: pause again twice, no revert
        vm.prank(PAUSE_ALL_OWNER_BOT);
        pauseAllLive.pauseAll();
        vm.prank(PAUSE_ALL_OWNER_BOT);
        pauseAllLive.pauseAll();
        assertTrue(PausableUpgradeable(address(market)).paused(), "still paused (idempotent)");
    }

    function testFork_Live_pauseAll_revertsForNonOwner() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        pauseAllLive.pauseAll();
    }
}
