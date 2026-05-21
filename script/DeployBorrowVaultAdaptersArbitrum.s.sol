// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Networks} from "@rheo-fm/script/Networks.sol";

import {AaveAdapter} from "@rheo-fm/src/market/token/adapters/AaveAdapter.sol";
import {ERC4626Adapter} from "@rheo-fm/src/market/token/adapters/ERC4626Adapter.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 2b — deploys `AaveAdapter` and `ERC4626Adapter` for the USDC borrow vault.
/// @dev    EOA broadcast, no admin role required. Run after Phase 2a is on-chain and the new
///         vault proxy address is known.
///
///         Required env vars:
///           - BORROW_TOKEN_VAULT   The svUSDC proxy from the Phase 2a Safe execution
///
///         Run:
///           forge script script/DeployBorrowVaultAdaptersArbitrum.s.sol \
///             --rpc-url arbitrum-production \
///             --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
///             --ffi --verify --broadcast -vvv
contract DeployBorrowVaultAdaptersArbitrumScript is BaseScript, Networks {
    function run() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        NonTransferrableRebasingTokenVault vault =
            NonTransferrableRebasingTokenVault(payable(vm.envAddress("BORROW_TOKEN_VAULT")));
        require(address(vault).code.length > 0, "BORROW_TOKEN_VAULT has no code at the given address");

        vm.startBroadcast();
        AaveAdapter aaveAdapter = new AaveAdapter(vault);
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(vault);
        vm.stopBroadcast();

        console.log("[Phase 2b] BorrowTokenVault (existing)", address(vault));
        console.log("[Phase 2b] AaveAdapter      (new)     ", address(aaveAdapter));
        console.log("[Phase 2b] ERC4626Adapter   (new)     ", address(erc4626Adapter));
        console.log("");
        console.log("Next: export both adapter addresses and run ProposeSafeTxWireBorrowVaultAdaptersArbitrum.s.sol");
        console.log("  export AAVE_ADAPTER=", address(aaveAdapter));
        console.log("  export ERC4626_ADAPTER=", address(erc4626Adapter));
    }
}
