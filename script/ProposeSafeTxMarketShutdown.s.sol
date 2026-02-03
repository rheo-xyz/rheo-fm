// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {GetMarketShutdownCalldataScript} from "@script/GetMarketShutdownCalldata.s.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";
import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";
import {MarketShutdownParams} from "@src/market/libraries/actions/MarketShutdown.sol";
import {WithdrawParams} from "@src/market/libraries/actions/Withdraw.sol";

contract ProposeSafeTxMarketShutdownScript is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;

    string[] public collateralMarketsToShutdownMainnet = ["PT-wstUSR-29JAN2026", "WBTC", "weETH", "cbETH"];
    string[] public collateralMarketsToShutdownBase = ["VIRTUAL", "cbETH"];

    uint256 constant SUPPLEMENT_USDC = 1_000e6;

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        _;
    }

    function run() external parseEnv {
        vm.createSelectFork("mainnet");

        (address[] memory targets, bytes[] memory datas) = getMarketShutdownData();

        safe.proposeTransactions(targets, datas, signer, derivationPath);
    }

    function getMarketShutdownData() public returns (address[] memory targets, bytes[] memory datas) {
        ISizeFactory sizeFactory = ISizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
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

        uint256 totalCalls = 2 + marketsToShutdown.length * 2;
        targets = new address[](totalCalls);
        datas = new bytes[](totalCalls);

        uint256 index = 0;
        GetMarketShutdownCalldataScript getMarketShutdownCalldataScript = new GetMarketShutdownCalldataScript();

        targets[index] = address(remainingMarket);
        datas[index] = abi.encodeCall(
            ISize.deposit,
            (
                DepositParams({
                    token: address(underlyingBorrowToken),
                    amount: SUPPLEMENT_USDC,
                    to: address(contracts[block.chainid][Contract.SIZE_GOVERNANCE])
                })
            )
        );
        index++;

        for (uint256 i = 0; i < marketsToShutdown.length; i++) {
            ISize market = marketsToShutdown[i];
            MarketShutdownParams memory params = getMarketShutdownCalldataScript.collectPositions(market);
            targets[index] = address(market);
            datas[index] = abi.encodeCall(ISizeAdmin.marketShutdown, (params));
            index++;

            targets[index] = address(market);
            datas[index] = abi.encodeCall(ISizeAdmin.pause, ());
            index++;
        }

        targets[index] = address(remainingMarket);
        datas[index] = abi.encodeCall(
            ISize.withdraw,
            (
                WithdrawParams({
                    token: address(underlyingBorrowToken),
                    amount: type(uint256).max,
                    to: address(contracts[block.chainid][Contract.SIZE_GOVERNANCE])
                })
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
