// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {GetMarketShutdownCalldataScript} from "@rheo-fm/script/GetMarketShutdownCalldata.s.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IMulticall} from "@rheo-fm/src/market/interfaces/IMulticall.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";

import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";

contract ProposeSafeTxMarketShutdownScript is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;

    string[] public collateralMarketsToShutdownMainnet = ["PT-wstUSR-29JAN2026", "WBTC", "weETH", "cbETH"];
    string[] public collateralMarketsToShutdownBase = ["VIRTUAL", "cbETH"];

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.RHEO_GOVERNANCE]);
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        _;
    }

    function run() external parseEnv {
        (address[] memory targets, bytes[] memory datas) = getMarketShutdownData();

        safe.proposeTransactions(targets, datas, signer, derivationPath);
    }

    function getMarketShutdownData() public returns (address[] memory targets, bytes[] memory datas) {
        IRheoFactory sizeFactory = IRheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        IRheo[] memory marketsToShutdown = _getMarketsToShutdown(sizeFactory);
        IRheo remainingMarket = _getRemainingMarket(sizeFactory, marketsToShutdown);

        IERC20Metadata underlyingBorrowToken = remainingMarket.data().underlyingBorrowToken;
        uint256 depositAmount = underlyingBorrowToken.balanceOf(contracts[block.chainid][Contract.RHEO_GOVERNANCE]);

        uint256 totalCalls = marketsToShutdown.length + 2 + (depositAmount > 0 ? 3 : 0);
        targets = new address[](totalCalls);
        datas = new bytes[](totalCalls);

        uint256 index = 0;
        GetMarketShutdownCalldataScript getMarketShutdownCalldataScript = new GetMarketShutdownCalldataScript();

        if (depositAmount > 0) {
            targets[index] = address(underlyingBorrowToken);
            datas[index] = abi.encodeCall(IERC20.approve, (address(remainingMarket), depositAmount));
            index++;

            targets[index] = address(remainingMarket);
            datas[index] = abi.encodeCall(
                IRheo.deposit,
                (
                    DepositParams({
                        token: address(underlyingBorrowToken),
                        amount: depositAmount,
                        to: contracts[block.chainid][Contract.RHEO_GOVERNANCE]
                    })
                )
            );
            index++;
        }

        index = _appendMarketShutdownCalls(getMarketShutdownCalldataScript, marketsToShutdown, targets, datas, index);

        targets[index] = address(remainingMarket);
        datas[index] = abi.encodeCall(
            IRheo.withdraw,
            (
                WithdrawParams({
                    token: address(underlyingBorrowToken),
                    amount: type(uint256).max,
                    to: address(contracts[block.chainid][Contract.RHEO_GOVERNANCE])
                })
            )
        );
        index++;

        bytes[] memory removeMarketData = new bytes[](marketsToShutdown.length);
        for (uint256 i = 0; i < marketsToShutdown.length; i++) {
            removeMarketData[i] = abi.encodeCall(IRheoFactory.removeMarket, (address(marketsToShutdown[i])));
        }
        targets[index] = address(sizeFactory);
        datas[index] = abi.encodeCall(IMulticall.multicall, (removeMarketData));
        index++;

        if (depositAmount > 0) {
            targets[index] = address(underlyingBorrowToken);
            datas[index] = abi.encodeCall(IERC20.approve, (address(remainingMarket), 0));
            index++;
        }

        require(index == totalCalls, "invalid index");
    }

    function _appendMarketShutdownCalls(
        GetMarketShutdownCalldataScript script,
        IRheo[] memory marketsToShutdown,
        address[] memory targets,
        bytes[] memory datas,
        uint256 index
    ) internal returns (uint256) {
        for (uint256 i = 0; i < marketsToShutdown.length; i++) {
            IRheo market = marketsToShutdown[i];
            targets[index] = address(market);
            datas[index] = _buildMarketShutdownAndOrPauseCall(script, market);
            index++;
        }
        return index;
    }

    function _getMarketsToShutdown(IRheoFactory sizeFactory) internal view returns (IRheo[] memory marketsToShutdown) {
        string[] memory collateralMarketsToShutdown = block.chainid == 1
            ? collateralMarketsToShutdownMainnet
            : block.chainid == 8453 ? collateralMarketsToShutdownBase : new string[](0);

        marketsToShutdown = new IRheo[](collateralMarketsToShutdown.length);
        for (uint256 i = 0; i < collateralMarketsToShutdown.length; i++) {
            marketsToShutdown[i] = _getMarket(sizeFactory, collateralMarketsToShutdown[i], "USDC");
        }
    }

    function _getRemainingMarket(IRheoFactory sizeFactory, IRheo[] memory marketsToShutdown)
        internal
        view
        returns (IRheo)
    {
        return difference(getUnpausedMarkets(sizeFactory), marketsToShutdown)[0];
    }

    function _buildMarketShutdownAndOrPauseCall(GetMarketShutdownCalldataScript script, IRheo market)
        internal
        returns (bytes memory)
    {
        DataView memory dataView = IRheoView(address(market)).data();
        bool isEmptyMarket = dataView.debtToken.totalSupply() == 0 && dataView.collateralToken.totalSupply() == 0;

        if (isEmptyMarket) {
            return abi.encodeCall(IRheoAdmin.pause, ());
        } else {
            MarketShutdownParams memory params = script.collectPositions(market);
            bytes[] memory multicallDatas = new bytes[](2);
            multicallDatas[0] = abi.encodeCall(IRheoAdmin.marketShutdown, (params));
            multicallDatas[1] = abi.encodeCall(IRheoAdmin.pause, ());
            return abi.encodeCall(IMulticall.multicall, (multicallDatas));
        }
    }

    function difference(IRheo[] memory outer, IRheo[] memory inner) public pure returns (IRheo[] memory result) {
        result = new IRheo[](outer.length);
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
