// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";
import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {Safe} from "@safe-utils/Safe.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {IMorphoChainlinkOracleV2} from "@rheo-fm/src/oracle/adapters/morpho/IMorphoChainlinkOracleV2.sol";
import {PriceFeedMorphoChainlinkOracleV2} from "@rheo-fm/src/oracle/v1.7.1/PriceFeedMorphoChainlinkOracleV2.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {PendleChainlinkOracle} from "@pendle/contracts/oracles/PtYtLpOracle/chainlink/PendleChainlinkOracle.sol";
import {PendleSparkLinearDiscountOracle} from "@pendle/contracts/oracles/internal/PendleSparkLinearDiscountOracle.sol";
import {PriceFeedPendleSparkLinearDiscountChainlink} from
    "@rheo-fm/src/oracle/v1.7.1/PriceFeedPendleSparkLinearDiscountChainlink.sol";
import {PriceFeedPendleTWAPChainlink} from "@rheo-fm/src/oracle/v1.7.2/PriceFeedPendleTWAPChainlink.sol";

import {console} from "forge-std/console.sol";

contract ProposeSafeTxDeployPTMarketScript is BaseScript, Networks {
    using Tenderly for *;
    using Safe for *;

    address signer;
    string derivationPath;

    IRheoFactory private sizeFactory;
    address private safeAddress;

    IERC20Metadata private underlyingCollateralToken;
    IPriceFeed private priceFeed;

    modifier parseEnv() {
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        sizeFactory = IRheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);

        string memory accountSlug = vm.envString("TENDERLY_ACCOUNT_NAME");
        string memory projectSlug = vm.envString("TENDERLY_PROJECT_NAME");
        string memory accessKey = vm.envString("TENDERLY_ACCESS_KEY");

        tenderly.initialize(accountSlug, projectSlug, accessKey);

        safeAddress = vm.envAddress("OWNER");
        safe.initialize(safeAddress);

        priceFeed = IPriceFeed(vm.envAddress("PRICE_FEED"));
        underlyingCollateralToken = IERC20Metadata(vm.envAddress("UNDERLYING_COLLATERAL_TOKEN"));

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        IRheo market = sizeFactory.getMarket(1);
        InitializeFeeConfigParams memory feeConfigParams = market.feeConfig();

        InitializeRiskConfigParams memory riskConfigParams = market.riskConfig();

        InitializeOracleParams memory oracleParams = market.oracle(); // priceFeed replaced below
        oracleParams.priceFeed = address(priceFeed);

        DataView memory dataView = market.data();
        InitializeDataParams memory dataParams = InitializeDataParams({
            weth: contracts[block.chainid][Contract.WETH],
            underlyingCollateralToken: address(underlyingCollateralToken),
            underlyingBorrowToken: address(dataView.underlyingBorrowToken),
            variablePool: address(dataView.variablePool),
            borrowTokenVault: address(dataView.borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });
        bytes memory data =
            abi.encodeCall(IRheoFactory.createMarket, (feeConfigParams, riskConfigParams, oracleParams, dataParams));
        address target = address(sizeFactory);
        safe.proposeTransaction(target, data, signer, derivationPath);
        Tenderly.VirtualTestnet memory vnet = tenderly.createVirtualTestnet("pt-market-vnet", block.chainid);
        bytes memory execTransactionData = safe.getExecTransactionData(target, data, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTransactionData);
    }
}
