// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {Safe} from "@safe-utils/Safe.sol";

import {PriceFeedChainlinkOnly4x} from "@rheo-fm/deprecated/oracle/v1.8/PriceFeedChainlinkOnly4x.sol";
import {MainnetAddresses} from "@rheo-fm/script/MainnetAddresses.s.sol";
import {PriceFeedChainlinkMul} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkMul.sol";
import {PriceFeedChainlinkOnly4xV2} from "@rheo-fm/src/oracle/v1.8/PriceFeedChainlinkOnly4xV2.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {console} from "forge-std/console.sol";

contract ProposeSafeTxUpdatePriceFeedChainlinkOnly4xV2Script is BaseScript, Networks, MainnetAddresses {
    using Safe for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    address signer;
    string derivationPath;
    IRheoFactory private sizeFactory;
    EnumerableSet.AddressSet private legacyCollaterals;

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.RHEO_GOVERNANCE]);
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        sizeFactory = IRheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        _;
    }

    function run() external parseEnv {
        vm.createSelectFork("mainnet");

        vm.startBroadcast();

        (address[] memory targets, bytes[] memory datas) = getUpdatePriceFeedsCalldata();

        vm.stopBroadcast();

        safe.proposeTransactions(targets, datas, signer, derivationPath);
    }

    function getUpdatePriceFeedsCalldata() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = IRheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        _seedLegacyCollaterals();

        (PriceFeedParams memory susdeChainlinkParams, PriceFeedParams memory susdeUniswapBaseParams,) =
            priceFeedsUSDeToUsdcMainnet();
        address susde = address(susdeUniswapBaseParams.baseToken);

        IRheo[] memory markets = sizeFactory.getMarkets();
        uint256 count;

        for (uint256 i = 0; i < markets.length; i++) {
            address underlyingCollateralToken = address(markets[i].data().underlyingCollateralToken);
            address underlyingBorrowToken = address(markets[i].data().underlyingBorrowToken);
            if (underlyingBorrowToken != USDC) {
                continue;
            }
            if (legacyCollaterals.contains(underlyingCollateralToken) || underlyingCollateralToken == susde) {
                count++;
            }
        }

        targets = new address[](count);
        datas = new bytes[](count);
        uint256 index;

        for (uint256 i = 0; i < markets.length; i++) {
            address underlyingCollateralToken = address(markets[i].data().underlyingCollateralToken);
            address underlyingBorrowToken = address(markets[i].data().underlyingBorrowToken);
            if (underlyingBorrowToken != USDC) {
                continue;
            }

            if (!legacyCollaterals.contains(underlyingCollateralToken) && underlyingCollateralToken != susde) {
                continue;
            }

            IPriceFeed oldFeed = IPriceFeed(markets[i].oracle().priceFeed);
            PriceFeedChainlinkOnly4xV2 updated = underlyingCollateralToken == susde
                ? _deploySusdeUsdcChainlinkOnly(susdeChainlinkParams)
                : _deployV2FromLegacy(PriceFeedChainlinkOnly4x(address(oldFeed)));

            targets[index] = address(markets[i]);
            datas[index] = abi.encodeCall(
                IRheoAdmin.updateConfig,
                (UpdateConfigParams({key: "priceFeed", value: uint256(uint160(address(updated)))}))
            );

            string memory logMessage = string.concat(
                "market",
                " ",
                vm.toString(address(markets[i])),
                " (",
                IERC20Metadata(underlyingCollateralToken).symbol(),
                "/",
                IERC20Metadata(underlyingBorrowToken).symbol(),
                ") ",
                "\n\told price feed ",
                vm.toString(address(oldFeed)),
                " (",
                price(oldFeed),
                ")",
                "\n\tnew price feed ",
                vm.toString(address(updated)),
                " (",
                price(updated),
                ")"
            );
            console.log(logMessage);

            index++;
        }
    }

    function _deployV2FromLegacy(PriceFeedChainlinkOnly4x legacy) internal returns (PriceFeedChainlinkOnly4xV2) {
        PriceFeedChainlinkMul baseMul = legacy.baseToIntermediate1();
        PriceFeedChainlinkMul quoteMul = legacy.quoteToIntermediate2();

        return new PriceFeedChainlinkOnly4xV2(
            baseMul.baseAggregator(),
            baseMul.quoteAggregator(),
            quoteMul.baseAggregator(),
            quoteMul.quoteAggregator(),
            baseMul.baseStalePriceInterval(),
            baseMul.quoteStalePriceInterval(),
            quoteMul.baseStalePriceInterval(),
            quoteMul.quoteStalePriceInterval()
        );
    }

    function _deploySusdeUsdcChainlinkOnly(PriceFeedParams memory chainlinkParams)
        internal
        returns (PriceFeedChainlinkOnly4xV2)
    {
        return new PriceFeedChainlinkOnly4xV2(
            chainlinkParams.baseAggregator,
            chainlinkParams.baseAggregator,
            chainlinkParams.quoteAggregator,
            chainlinkParams.quoteAggregator,
            chainlinkParams.baseStalePriceInterval,
            chainlinkParams.baseStalePriceInterval,
            chainlinkParams.quoteStalePriceInterval,
            chainlinkParams.quoteStalePriceInterval
        );
    }

    function _seedLegacyCollaterals() internal {
        if (legacyCollaterals.length() > 0) {
            return;
        }
        legacyCollaterals.add(WBTC);
        legacyCollaterals.add(cbBTC);
        legacyCollaterals.add(WETH);
        legacyCollaterals.add(weETH);
        legacyCollaterals.add(cbETH);
    }
}
