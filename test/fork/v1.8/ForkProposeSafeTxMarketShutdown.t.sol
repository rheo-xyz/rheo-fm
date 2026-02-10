// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {ProposeSafeTxMarketShutdownScript} from "@rheo-fm/script/ProposeSafeTxMarketShutdown.s.sol";
import {ProposeSafeTxUpgradeToV1_8_4Script} from "@rheo-fm/script/ProposeSafeTxUpgradeToV1_8_4.s.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";

import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";
import {Math} from "@rheo-fm/src/market/libraries/Math.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

import {console} from "forge-std/console.sol";

contract ForkProposeSafeTxMarketShutdownTest is ForkTest, Networks {
    uint256 private constant MAINNET_BLOCK = 24_385_645;
    uint256 private constant BASE_BLOCK = 41_722_440;
    uint256 private constant MAINNET_MARKETS = 4;
    uint256 private constant BASE_MARKETS = 2;

    function setUp() public override(ForkTest) {}

    function testFork_ProposeSafeTxMarketShutdown_mainnet() public {
        _resetFork("mainnet", MAINNET_BLOCK, ETHEREUM_MAINNET);
        _executeProposeSafeTxMarketShutdown();
    }

    function testFork_ProposeSafeTxMarketShutdown_base() public {
        _resetFork("base_archive", BASE_BLOCK, BASE_MAINNET);
        _executeProposeSafeTxMarketShutdown();
    }

    function _resetFork(string memory rpcAlias, uint256 blockNumber, uint256 chainId) internal {
        vm.createSelectFork(rpcAlias, blockNumber);
        vm.chainId(chainId);

        sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        owner = contracts[block.chainid][Contract.RHEO_GOVERNANCE];
    }

    function _executeProposeSafeTxMarketShutdown() internal {
        _upgradeToV1_8_4();

        ProposeSafeTxMarketShutdownScript script = new ProposeSafeTxMarketShutdownScript();
        (address[] memory targets, bytes[] memory datas) = script.getMarketShutdownData();

        IRheo[] memory marketsToShutdown = _getMarketsToShutdown(script);

        IRheo[] memory remainingMarkets = script.difference(getUnpausedMarkets(sizeFactory), marketsToShutdown);
        IRheo remainingMarket = remainingMarkets[0];

        _executeShutdown(
            targets, datas, marketsToShutdown, remainingMarket, remainingMarket.data().underlyingBorrowToken
        );
    }

    function _executeShutdown(
        address[] memory targets,
        bytes[] memory datas,
        IRheo[] memory marketsToShutdown,
        IRheo remainingMarket,
        IERC20Metadata underlyingBorrowToken
    ) internal {
        (IERC20Metadata[] memory collateralTokens, IPriceFeed[] memory priceFeeds, uint256 collateralCount) =
            _collectCollateralTokens(marketsToShutdown);

        uint256 borrowBefore = underlyingBorrowToken.balanceOf(owner);
        uint256[] memory collateralBefore = new uint256[](collateralCount);
        for (uint256 i = 0; i < collateralCount; i++) {
            collateralBefore[i] = collateralTokens[i].balanceOf(owner);
        }

        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }

        _assertMarketsShutdown(marketsToShutdown);
        _assertMarketsRemoved(marketsToShutdown);
        assertFalse(PausableUpgradeable(address(remainingMarket)).paused());
        assertTrue(sizeFactory.isMarket(address(remainingMarket)));

        uint256 borrowAfter = underlyingBorrowToken.balanceOf(owner);
        int256 borrowDelta = int256(borrowAfter) - int256(borrowBefore);
        uint8 borrowDecimals = underlyingBorrowToken.decimals();

        _logTokenDelta(underlyingBorrowToken.symbol(), borrowDelta, borrowDecimals);

        int256 usdcDelta = borrowDelta;
        for (uint256 i = 0; i < collateralCount; i++) {
            uint256 afterBalance = collateralTokens[i].balanceOf(owner);
            int256 delta = int256(afterBalance) - int256(collateralBefore[i]);
            _logTokenDelta(collateralTokens[i].symbol(), delta, collateralTokens[i].decimals());
            usdcDelta += _toUsdcDelta(delta, collateralTokens[i], priceFeeds[i], borrowDecimals);
        }

        _logUsdcAggregate(usdcDelta, borrowDecimals);
    }

    function _upgradeToV1_8_4() internal {
        ProposeSafeTxUpgradeToV1_8_4Script upgradeScript = new ProposeSafeTxUpgradeToV1_8_4Script();
        (address[] memory targets, bytes[] memory datas) = upgradeScript.getUpgradeToV1_8_4Data();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }
    }

    function _getMarketsToShutdown(ProposeSafeTxMarketShutdownScript script)
        internal
        view
        returns (IRheo[] memory markets)
    {
        if (block.chainid == ETHEREUM_MAINNET) {
            markets = new IRheo[](MAINNET_MARKETS);
            for (uint256 i = 0; i < MAINNET_MARKETS; i++) {
                markets[i] = _findMarket(script.collateralMarketsToShutdownMainnet(i), "USDC");
            }
        } else if (block.chainid == BASE_MAINNET) {
            markets = new IRheo[](BASE_MARKETS);
            for (uint256 i = 0; i < BASE_MARKETS; i++) {
                markets[i] = _findMarket(script.collateralMarketsToShutdownBase(i), "USDC");
            }
        } else {
            revert("unsupported chain");
        }
    }

    function _assertMarketsShutdown(IRheo[] memory markets) internal view {
        for (uint256 i = 0; i < markets.length; i++) {
            IRheo market = markets[i];
            assertTrue(PausableUpgradeable(address(market)).paused());
            DataView memory dataView = IRheoView(address(market)).data();
            assertEq(dataView.debtToken.totalSupply(), 0);
            assertEq(dataView.collateralToken.totalSupply(), 0);
        }
    }

    function _assertMarketsRemoved(IRheo[] memory markets) internal view {
        for (uint256 i = 0; i < markets.length; i++) {
            assertFalse(sizeFactory.isMarket(address(markets[i])));
        }
    }

    function _collectCollateralTokens(IRheo[] memory markets)
        internal
        view
        returns (IERC20Metadata[] memory tokens, IPriceFeed[] memory priceFeeds, uint256 count)
    {
        tokens = new IERC20Metadata[](markets.length);
        priceFeeds = new IPriceFeed[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            IRheo market = markets[i];
            IERC20Metadata collateral = IRheoView(address(market)).data().underlyingCollateralToken;
            bool exists = false;
            for (uint256 j = 0; j < count; j++) {
                if (address(tokens[j]) == address(collateral)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                tokens[count] = collateral;
                priceFeeds[count] = IPriceFeed(IRheoView(address(market)).oracle().priceFeed);
                count++;
            }
        }
    }

    function _toUsdcDelta(
        int256 collateralDelta,
        IERC20Metadata collateralToken,
        IPriceFeed priceFeed,
        uint8 borrowDecimals
    ) internal view returns (int256) {
        if (collateralDelta == 0) {
            return 0;
        }
        uint256 absDelta = collateralDelta < 0 ? uint256(-collateralDelta) : uint256(collateralDelta);
        uint256 price = priceFeed.getPrice();
        uint256 priceDecimals = priceFeed.decimals();
        uint256 collateralDecimals = collateralToken.decimals();
        uint256 usdcValueAbs = Math.mulDivDown(
            absDelta, price * 10 ** uint256(borrowDecimals), 10 ** priceDecimals * 10 ** collateralDecimals
        );
        return collateralDelta < 0 ? -int256(usdcValueAbs) : int256(usdcValueAbs);
    }

    function _logTokenDelta(string memory symbol, int256 delta, uint8 decimals) internal pure {
        if (delta == 0) {
            console.log(string.concat("admin delta ", symbol, ": ZERO"));
            return;
        }
        string memory sign = delta >= 0 ? "+" : "-";
        uint256 absDelta = delta >= 0 ? uint256(delta) : uint256(-delta);
        console.log(string.concat("admin delta ", symbol, ": ", sign, format(absDelta, decimals, 2)));
    }

    function _logUsdcAggregate(int256 usdcDelta, uint8 usdcDecimals) internal pure {
        if (usdcDelta == 0) {
            console.log("admin aggregate usdcDelta: ZERO");
            return;
        }
        string memory sign = usdcDelta >= 0 ? "+" : "-";
        uint256 absDelta = usdcDelta >= 0 ? uint256(usdcDelta) : uint256(-usdcDelta);
        console.log(string.concat("admin aggregate usdcDelta: ", sign, format(absDelta, usdcDecimals, 2)));
    }
}
