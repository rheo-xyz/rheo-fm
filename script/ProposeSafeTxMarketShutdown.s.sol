// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Safe} from "@safe-utils/Safe.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

contract ProposeSafeTxMarketShutdownScript is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;
    ISizeFactory private sizeFactory;

    string[] private collateralMarketsToShutdownMainnet = ["PT-wstUSR-29JAN2026", "WBTC", "weETH", "cbETH"];
    string[] private collateralMarketsToShutdownBase = ["VIRTUAL", "cbETH"];

    uint256 constant SUPPLEMENT_USDC = 1_000e6;

    address[] private targets;
    bytes[] private datas;

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
    }

    function run() external parseEnv {
        vm.createSelectFork("mainnet");

        (address[] memory targets, bytes[] memory datas) = getMarketShutdownData();

        safe.proposeTransactions(targets, datas, signer, derivationPath);
    }

    function getMarketShutdownData() public returns (address[] memory targets, bytes[] memory datas) {
        ISize[] memory unpausedMarkets = getUnpausedMarkets(sizeFactory);

        string[] memory collateralMarketsToShutdown = block.chainid == 1
            ? collateralMarketsToShutdownMainnet
            : block.chainid == 8453 ? collateralMarketsToShutdownBase : new string[](0);

        ISize[] memory marketsToShutdown = new ISize[](collateralMarketsToShutdown.length);
        for (uint256 i = 0; i < collateralMarketsToShutdown.length; i++) {
            marketsToShutdown[i] = _getMarket(sizeFactory, collateralMarketsToShutdown[i], "USDC");
        }

        ISize remainingMarket = difference(unpausedMarkets, marketsToShutdown)[0];
        IERC20Metadata underlyingBorrowToken = remainingMarket.data().underlyingBorrowToken;

        GetMarketShutdownCalldataScript getMarketShutdownCalldataScript = new GetMarketShutdownCalldataScript();

        targets.push(address(remainingMarket));
        datas.push(
            abi.encodeCall(
                ISize.deposit,
                (
                    DepositParams({
                        token: address(underlyingBorrowToken),
                        amount: SUPPLEMENT_USDC,
                        to: address(contracts[block.chainid][Contract.SIZE_GOVERNANCE])
                    })
                )
            )
        );

        for (uint256 i = 0; i < marketsToShutdown.length; i++) {
            ISize market = marketsToShutdown[i];
            MarketShutdownParams memory params = getMarketShutdownCalldataScript.collectPositions(market);
            targets.push(address(market));
            datas.push(abi.encodeCall(ISizeAdmin.marketShutdown, (params)));

            targets.push(address(market));
            datas.push(abi.encodeCall(ISizeAdmin.pause, ()));
        }

        targets.push(address(remainingMarket));
        datas.push(
            abi.encodeCall(
                ISize.withdraw,
                (
                    WithdrawParams({
                        token: address(underlyingBorrowToken),
                        amount: type(uint256).max,
                        to: address(contracts[block.chainid][Contract.SIZE_GOVERNANCE])
                    })
                )
            )
        );
    }

    function difference(ISize[] memory outer, ISize[] memory inner) internal pure returns (ISize[] memory result) {
        result = new ISize[](outer.length);
        uint256 resultLength = 0;
        for (uint256 i = 0; i < outer.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < inner.length; j++) {
                if (outer[i] == inner[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                result[resultLength++] = outer[i];
            }
        }
        _unsafeSetLength(result, resultLength);
    }
}
