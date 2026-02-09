// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";
import {Safe} from "@safe-utils/Safe.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PendleSparkLinearDiscountOracle} from "@pendle/contracts/oracles/internal/PendleSparkLinearDiscountOracle.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {PriceFeedPendleSparkLinearDiscountChainlink} from
    "@rheo-fm/src/oracle/v1.7.1/PriceFeedPendleSparkLinearDiscountChainlink.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console} from "forge-std/console.sol";

contract ProposeSafeTxDeployPTPriceFeedScript is BaseScript, Networks {
    using Tenderly for *;
    using Safe for *;

    address signer;
    string derivationPath;

    IRheoFactory private sizeFactory;
    address private safeAddress;

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

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        vm.createSelectFork("mainnet");
        (IPriceFeed priceFeed,,,,,,,) = priceFeedPendleChainlink29May2025UsdcMainnet();

        IRheo market = sizeFactory.getMarket(1);
        IPriceFeed oldPriceFeed = IPriceFeed(market.oracle().priceFeed);
        uint256 oldPrice = oldPriceFeed.getPrice();
        console.log("old Price Feed", address(oldPriceFeed));

        console.log("oldPrice", oldPrice);

        console.log("new Price Feed", address(priceFeed));

        bytes memory data = abi.encodeCall(
            IRheoAdmin.updateConfig,
            (UpdateConfigParams({key: "priceFeed", value: uint256(uint160(address(priceFeed)))}))
        );
        address to = address(market);
        safe.proposeTransaction(to, data, signer, derivationPath);
        Tenderly.VirtualTestnet memory vnet = tenderly.createVirtualTestnet("pt-price-feed-vnet", block.chainid);
        bytes memory execTransactionData = safe.getExecTransactionData(to, data, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTransactionData);

        vm.createSelectFork(vnet.getPublicRpcUrl());

        uint256 newPrice = IPriceFeed(market.oracle().priceFeed).getPrice();
        console.log("newPrice", newPrice);

        require(int256(newPrice) - int256(oldPrice) <= 0.01e18, "Price is not close to old price");
    }
}
