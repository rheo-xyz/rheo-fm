// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script} from
    "@rheo-fm/script/ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2.s.sol";
import {ProposeSafeTxUpgradeToV1_8_4Script} from "@rheo-fm/script/ProposeSafeTxUpgradeToV1_8_4.s.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";

import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";

import {InitializeRiskConfigParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math} from "@rheo-fm/src/market/libraries/Math.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

contract ForkProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Test is ForkTest, Networks {
    uint256 private constant MAINNET_BLOCK = 24_385_645;
    uint256 private constant BASE_BLOCK = 41_946_442;

    function setUp() public override(ForkTest) {}

    function testFork_ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2_mainnet() public {
        _resetFork("mainnet", MAINNET_BLOCK, ETHEREUM_MAINNET);
        _executeUpgradeAndAssertFixed();
    }

    function testFork_ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2_base() public {
        _resetFork("base_archive", BASE_BLOCK, BASE_MAINNET);
        _executeUpgradeAndAssertFixed();
    }

    function _resetFork(string memory rpcAlias, uint256 blockNumber, uint256 chainId) internal {
        vm.createSelectFork(rpcAlias, blockNumber);
        vm.chainId(chainId);

        sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        owner = contracts[block.chainid][Contract.RHEO_GOVERNANCE];
    }

    function _executeUpgradeAndAssertFixed() internal {
        _upgradeToV1_8_4();

        IRheo market = _findMarket("WETH", "USDC");
        assertEq(IRheoView(address(market)).version(), "v1.9");

        // Pre-upgrade: the on-chain CollectionsManager implementation still calls the legacy
        // per-offer null-check helpers, which are not implemented by v1.8.4 Size markets.
        _testSellCreditMarketShouldRevert(market);

        // Upgrade the CollectionsManager proxy via the same Safe-tx proposal flow we use in prod.
        ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script upgradeCollectionsManagerScript =
            new ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script();
        (address[] memory targets, bytes[] memory datas) =
            upgradeCollectionsManagerScript.getUpgradeCollectionsManagerV1_8_4_Update2Data();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }

        // Post-upgrade: market orders succeed against v1.8.4+ markets (Size and Rheo FM).
        _testSellCreditMarketShouldNotRevert(market);
    }

    function _upgradeToV1_8_4() internal {
        ProposeSafeTxUpgradeToV1_8_4Script upgradeScript = new ProposeSafeTxUpgradeToV1_8_4Script();
        (address[] memory targets, bytes[] memory datas) = upgradeScript.getUpgradeToV1_8_4Data();

        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }
    }

    function _testSellCreditMarketShouldRevert(IRheo market) internal {
        SellCreditMarketParams memory params = _buildAliceBobSellCreditMarketParams(market);

        vm.expectRevert();
        vm.prank(bob);
        market.sellCreditMarket(params);
    }

    function _testSellCreditMarketShouldNotRevert(IRheo market) internal {
        SellCreditMarketParams memory params = _buildAliceBobSellCreditMarketParams(market);

        uint256 nextDebtPositionIdBefore = IRheoView(address(market)).data().nextDebtPositionId;

        vm.prank(bob);
        market.sellCreditMarket(params);

        uint256 nextDebtPositionIdAfter = IRheoView(address(market)).data().nextDebtPositionId;
        assertEq(nextDebtPositionIdAfter, nextDebtPositionIdBefore + 1);
    }

    function _buildAliceBobSellCreditMarketParams(IRheo market)
        internal
        returns (SellCreditMarketParams memory params)
    {
        DataView memory dataView = IRheoView(address(market)).data();
        IERC20Metadata borrowToken = dataView.underlyingBorrowToken;
        IERC20Metadata collateralToken = dataView.underlyingCollateralToken;

        InitializeRiskConfigParams memory riskConfig = IRheoView(address(market)).riskConfig();
        uint256 maturity = riskConfig.maturities[0];
        uint256 creditAmountIn = riskConfig.minimumCreditBorrowToken;

        {
            // Lender: deposit borrow token and set a loan offer.
            uint256 lenderDepositAmount = creditAmountIn * 10;
            deal(address(borrowToken), alice, lenderDepositAmount);
            vm.prank(alice);
            borrowToken.approve(address(market), lenderDepositAmount);
            vm.prank(alice);
            market.deposit(DepositParams({token: address(borrowToken), amount: lenderDepositAmount, to: alice}));

            uint256[] memory maturities = new uint256[](1);
            maturities[0] = maturity;
            uint256[] memory aprs = new uint256[](1);
            aprs[0] = 0.1e18;
            vm.prank(alice);
            market.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));
        }

        {
            // Borrower: deposit collateral.
            uint256 collateralDepositAmount =
                _calcCollateralDepositAmount(market, borrowToken, collateralToken, creditAmountIn, riskConfig.crOpening);
            deal(address(collateralToken), bob, collateralDepositAmount);
            vm.prank(bob);
            collateralToken.approve(address(market), collateralDepositAmount);
            vm.prank(bob);
            market.deposit(DepositParams({token: address(collateralToken), amount: collateralDepositAmount, to: bob}));
        }

        // Borrower: sell credit as a market order.
        params = SellCreditMarketParams({
            lender: alice,
            creditPositionId: RESERVED_ID,
            amount: creditAmountIn,
            maturity: maturity,
            deadline: block.timestamp,
            maxAPR: type(uint256).max,
            exactAmountIn: true,
            collectionId: RESERVED_ID,
            rateProvider: address(0)
        });
    }

    function _calcCollateralDepositAmount(
        IRheo market,
        IERC20Metadata borrowToken,
        IERC20Metadata collateralToken,
        uint256 creditAmountIn,
        uint256 crOpening
    ) internal view returns (uint256 collateralDepositAmount) {
        uint256 price = IPriceFeed(IRheoView(address(market)).oracle().priceFeed).getPrice();
        uint256 borrowDecimals = borrowToken.decimals();
        uint256 collateralDecimals = collateralToken.decimals();

        uint256 requiredCollateral =
            Math.mulDivUp(creditAmountIn * 10 ** collateralDecimals, crOpening, price * 10 ** borrowDecimals);

        // Headroom to avoid edge-case rounding causing CR checks to fail.
        collateralDepositAmount = requiredCollateral * 2 + 1;
    }
}
