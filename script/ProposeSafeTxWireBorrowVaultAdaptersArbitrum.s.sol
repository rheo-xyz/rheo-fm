// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {IAdapter} from "@rheo-fm/src/market/token/adapters/IAdapter.sol";
import {
    AAVE_ADAPTER_ID,
    DEFAULT_VAULT,
    ERC4626_ADAPTER_ID,
    NonTransferrableRebasingTokenVault
} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 2c — proposes one Safe transaction (delegateCall to MultiSendCallOnly) that
///         batches the three setters needed to wire the new adapters onto the USDC borrow vault:
///
///           - vault.setAdapter(AAVE_ADAPTER_ID, aaveAdapter)
///           - vault.setVaultAdapter(DEFAULT_VAULT, AAVE_ADAPTER_ID)   // make Aave the default
///           - vault.setAdapter(ERC4626_ADAPTER_ID, erc4626Adapter)
///
/// @dev    Two entry points:
///           - `run()` — pushes the proposal via Ledger + creates a Tenderly vnet.
///             Requires SIGNER, LEDGER_PATH, OWNER, BORROW_TOKEN_VAULT, AAVE_ADAPTER,
///             ERC4626_ADAPTER, TENDERLY_ACCOUNT_NAME, TENDERLY_PROJECT_NAME, TENDERLY_ACCESS_KEY.
///             Run:
///               forge script script/ProposeSafeTxWireBorrowVaultAdaptersArbitrum.s.sol \
///                 --rpc-url arbitrum-production --sender $SIGNER --account $DEPLOYER_ACCOUNT --ffi -vvv
///
///           - `printCalldata()` — prints the raw transaction payload for manual Safe-UI building.
///             Requires only OWNER, BORROW_TOKEN_VAULT, AAVE_ADAPTER, ERC4626_ADAPTER.
///             Run:
///               forge script script/ProposeSafeTxWireBorrowVaultAdaptersArbitrum.s.sol \
///                 --rpc-url arbitrum-production --sig "printCalldata()" -vvv
contract ProposeSafeTxWireBorrowVaultAdaptersArbitrumScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    address private signer;
    string private derivationPath;
    NonTransferrableRebasingTokenVault private vault;
    IAdapter private aaveAdapter;
    IAdapter private erc4626Adapter;

    modifier parseEnv() {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        address ownerEnv = vm.envAddress("OWNER");
        // F6: defense against .env typo that would sign from a non-canonical Safe.
        require(
            ownerEnv == contracts[block.chainid][Contract.RHEO_GOVERNANCE],
            "OWNER must equal contracts[ARBITRUM_MAINNET][RHEO_GOVERNANCE]"
        );
        safe.initialize(ownerEnv);

        vault = NonTransferrableRebasingTokenVault(payable(vm.envAddress("BORROW_TOKEN_VAULT")));
        aaveAdapter = IAdapter(vm.envAddress("AAVE_ADAPTER"));
        erc4626Adapter = IAdapter(vm.envAddress("ERC4626_ADAPTER"));

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address[] memory targets, bytes[] memory datas) = _buildCalls();

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-phase2c-wire-adapters-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionsData(targets, datas, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }

    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        address ownerEnv = vm.envAddress("OWNER");
        // F6: defense against .env typo that would sign from a non-canonical Safe.
        require(
            ownerEnv == contracts[block.chainid][Contract.RHEO_GOVERNANCE],
            "OWNER must equal contracts[ARBITRUM_MAINNET][RHEO_GOVERNANCE]"
        );
        safe.initialize(ownerEnv);

        vault = NonTransferrableRebasingTokenVault(payable(vm.envAddress("BORROW_TOKEN_VAULT")));
        aaveAdapter = IAdapter(vm.envAddress("AAVE_ADAPTER"));
        erc4626Adapter = IAdapter(vm.envAddress("ERC4626_ADAPTER"));

        (address[] memory targets, bytes[] memory datas) = _buildCalls();

        console.log("==============================================================================");
        console.log("OPTION A: Three separate transactions (Safe UI > New transaction > Contract interaction)");
        console.log("          For each, Operation = Call");
        console.log("==============================================================================");
        string[3] memory labels =
            ["setAdapter(AAVE_ADAPTER_ID, aaveAdapter)", "setVaultAdapter(DEFAULT_VAULT, AAVE_ADAPTER_ID)", "setAdapter(ERC4626_ADAPTER_ID, erc4626Adapter)"];
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("");
            console.log("Tx %s: %s", i + 1, labels[i]);
            console.log("  To:        %s", targets[i]);
            console.log("  Value:     0");
            console.log("  Operation: Call");
            console.log("  Data:");
            console.logBytes(datas[i]);
        }

        (address multiSendTarget, bytes memory multiSendData) =
            safe.getProposeTransactionsTargetAndData(targets, datas);

        console.log("");
        console.log("==============================================================================");
        console.log("OPTION B: One batched transaction (Safe UI > Transaction Builder > Custom data)");
        console.log("          Operation = DelegateCall");
        console.log("==============================================================================");
        console.log("");
        console.log("  To:        %s   (canonical MultiSendCallOnly on Arbitrum)", multiSendTarget);
        console.log("  Value:     0");
        console.log("  Operation: DelegateCall");
        console.log("  Data:");
        console.logBytes(multiSendData);
        console.log("");
    }

    function _buildCalls() private view returns (address[] memory targets, bytes[] memory datas) {
        targets = new address[](3);
        datas = new bytes[](3);

        targets[0] = address(vault);
        datas[0] = abi.encodeCall(NonTransferrableRebasingTokenVault.setAdapter, (AAVE_ADAPTER_ID, aaveAdapter));

        targets[1] = address(vault);
        datas[1] = abi.encodeCall(NonTransferrableRebasingTokenVault.setVaultAdapter, (DEFAULT_VAULT, AAVE_ADAPTER_ID));

        targets[2] = address(vault);
        datas[2] = abi.encodeCall(NonTransferrableRebasingTokenVault.setAdapter, (ERC4626_ADAPTER_ID, erc4626Adapter));
    }
}
