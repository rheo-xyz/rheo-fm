// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoV1_7} from "@rheo-fm/src/market/interfaces/v1.7/IRheoV1_7.sol";
import {IRheoV1_8} from "@rheo-fm/src/market/interfaces/v1.8/IRheoV1_8.sol";

import {DepositOnBehalfOfParams, DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {SetVaultOnBehalfOfParams, SetVaultParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";
import {WithdrawOnBehalfOfParams, WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";

contract MaliciousERC4626ReentrancyGeneric is ERC4626, Ownable {
    IRheo public size;
    bytes4 public operation;
    bool public forfeitOldShares;
    address public onBehalfOf;
    uint256 public reenterCount;

    constructor(IERC20 underlying_, string memory name_, string memory symbol_)
        ERC4626(underlying_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {}

    function setRheo(IRheo _size) external onlyOwner {
        size = _size;
    }

    function setForfeitOldShares(bool _forfeitOldShares) external onlyOwner {
        forfeitOldShares = _forfeitOldShares;
    }

    function setOnBehalfOf(address _onBehalfOf) external onlyOwner {
        onBehalfOf = _onBehalfOf;
    }

    function setReenterCount(uint256 _reenterCount) external onlyOwner {
        reenterCount = _reenterCount;
    }

    function setOperation(bytes4 _operation) external onlyOwner {
        bytes4[] memory operations = new bytes4[](4);
        operations[0] = IRheoV1_7.depositOnBehalfOf.selector;
        operations[1] = IRheoV1_7.withdrawOnBehalfOf.selector;
        operations[2] = IRheoV1_8.setVaultOnBehalfOf.selector;
        operations[3] = IERC20.approve.selector;
        operation = operations[uint256(uint32(_operation)) % operations.length];
    }

    function _reenter() internal {
        if (operation == IRheoV1_7.depositOnBehalfOf.selector) {
            size.depositOnBehalfOf(
                DepositOnBehalfOfParams({
                    params: DepositParams({
                        token: asset(),
                        amount: IERC20(asset()).balanceOf(address(this)),
                        to: address(this)
                    }),
                    onBehalfOf: onBehalfOf
                })
            );
        } else if (operation == IRheoV1_7.withdrawOnBehalfOf.selector) {
            size.withdrawOnBehalfOf(
                WithdrawOnBehalfOfParams({
                    params: WithdrawParams({token: asset(), amount: type(uint256).max, to: address(this)}),
                    onBehalfOf: onBehalfOf
                })
            );
        } else if (operation == IRheoV1_8.setVaultOnBehalfOf.selector) {
            size.setVaultOnBehalfOf(
                SetVaultOnBehalfOfParams({
                    params: SetVaultParams({vault: address(this), forfeitOldShares: forfeitOldShares}),
                    onBehalfOf: onBehalfOf
                })
            );
        } else if (operation == IERC20.approve.selector) {
            IERC20(asset()).approve(address(size), type(uint256).max);
        } else {
            revert Errors.NOT_SUPPORTED();
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (reenterCount > 0) {
            _reenter();
            reenterCount--;
        }

        super._update(from, to, value);

        if (reenterCount > 0) {
            _reenter();
            reenterCount--;
        }
    }
}
