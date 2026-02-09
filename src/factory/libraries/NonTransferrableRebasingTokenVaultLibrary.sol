// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";

import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

library NonTransferrableRebasingTokenVaultLibrary {
    function createNonTransferrableRebasingTokenVault(
        address implementation,
        address owner,
        IPool variablePool,
        IERC20Metadata underlyingBorrowToken
    ) external returns (NonTransferrableRebasingTokenVault token) {
        token = NonTransferrableRebasingTokenVault(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        NonTransferrableRebasingTokenVault.initialize,
                        (
                            IRheoFactory(address(this)),
                            variablePool,
                            underlyingBorrowToken,
                            owner,
                            string.concat("Rheo ", underlyingBorrowToken.name(), " Vault"),
                            string.concat("sv", underlyingBorrowToken.symbol()),
                            underlyingBorrowToken.decimals()
                        )
                    )
                )
            )
        );
    }
}
