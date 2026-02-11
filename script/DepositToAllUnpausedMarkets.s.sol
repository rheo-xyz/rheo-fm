// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {ISizeFactoryV1_7} from "@rheo-solidity/src/factory/interfaces/ISizeFactoryV1_7.sol";
import {ISizeFactoryV1_8} from "@rheo-solidity/src/factory/interfaces/ISizeFactoryV1_8.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoV1_7} from "@rheo-fm/src/market/interfaces/v1.7/IRheoV1_7.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {DepositOnBehalfOfParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {Authorization} from "@rheo-solidity/src/factory/libraries/Authorization.sol";
import {Action} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

import {console} from "forge-std/console.sol";

contract DepositToAllUnpausedMarketsScript is BaseScript, Networks {
    using SafeERC20 for IERC20Metadata;

    function run() external broadcast {
        ISizeFactory sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        address[] memory marketAddresses = sizeFactory.getMarkets();
        IRheo[] memory markets = new IRheo[](marketAddresses.length);
        for (uint256 i = 0; i < marketAddresses.length; i++) {
            markets[i] = IRheo(marketAddresses[i]);
        }
        IRheo[] memory unpausedMarkets = new IRheo[](markets.length);
        IERC20Metadata underlyingBorrowToken = IERC20Metadata(markets[0].data().underlyingBorrowToken);
        uint256 amount = 10 ** underlyingBorrowToken.decimals();
        uint256 unpausedMarketsLength = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            if (!PausableUpgradeable(address(markets[i])).paused()) {
                unpausedMarkets[unpausedMarketsLength] = markets[i];
                unpausedMarketsLength++;
            }
        }
        _unsafeSetLength(unpausedMarkets, unpausedMarketsLength);
        bytes[] memory datas = new bytes[](1 + unpausedMarketsLength + 1);
        datas[0] = abi.encodeCall(
            ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.getActionsBitmap(Action.DEPOSIT))
        );
        for (uint256 i = 0; i < unpausedMarketsLength; i++) {
            underlyingBorrowToken.forceApprove(address(unpausedMarkets[i]), amount);
            datas[i + 1] = abi.encodeCall(
                ISizeFactoryV1_8.callMarket,
                (
                    address(unpausedMarkets[i]),
                    abi.encodeCall(
                        IRheoV1_7.depositOnBehalfOf,
                        (
                            DepositOnBehalfOfParams({
                                params: DepositParams({
                                    token: address(underlyingBorrowToken),
                                    amount: amount,
                                    to: address(unpausedMarkets[i])
                                }),
                                onBehalfOf: msg.sender
                            })
                        )
                    )
                )
            );
        }
        datas[unpausedMarketsLength + 1] =
            abi.encodeCall(ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.nullActionsBitmap()));
        MulticallUpgradeable(address(sizeFactory)).multicall(datas);
    }
}
