// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 1.2 wiring: proposes a single Safe transaction (delegateCall to MultiSendCallOnly)
///         that batches the three admin-only setters needed to make the SizeFactory usable.
///
///           - setRheoImplementation(rheoImpl)
///           - setNonTransferrableRebasingTokenVaultImplementation(vaultImpl)
///           - setCollectionsManager(collectionsManagerProxy)
///
/// @dev    Two entry points:
///           - `run()` — pushes the proposal to the Safe API via Ledger + creates a Tenderly vnet.
///             Requires SIGNER, LEDGER_PATH, OWNER, RHEO_IMPLEMENTATION, VAULT_IMPLEMENTATION,
///             COLLECTIONS_MANAGER, TENDERLY_ACCOUNT_NAME, TENDERLY_PROJECT_NAME, TENDERLY_ACCESS_KEY.
///             Run:
///               forge script script/ProposeSafeTxWireRheoArbitrumFactory.s.sol \
///                 --rpc-url arbitrum-production --sender $SIGNER --account $DEPLOYER_ACCOUNT --ffi -vvv
///
///           - `printCalldata()` — prints the raw transaction payload (3 individual setters AND the
///             batched MultiSendCallOnly delegateCall) so you can build the Safe tx manually in
///             the Safe Web UI's Transaction Builder. No Ledger, no Tenderly, no Safe API calls.
///             Requires only OWNER, RHEO_IMPLEMENTATION, VAULT_IMPLEMENTATION, COLLECTIONS_MANAGER.
///             Run:
///               forge script script/ProposeSafeTxWireRheoArbitrumFactory.s.sol \
///                 --rpc-url arbitrum-production --sig "printCalldata()" -vvv
contract ProposeSafeTxWireRheoArbitrumFactoryScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    address private signer;
    string private derivationPath;
    ISizeFactory private sizeFactory;
    address private rheoImplementation;
    address private vaultImplementation;
    ICollectionsManager private collectionsManager;

    /// @dev parseEnv runs BEFORE deleteVirtualTestnets so tenderly is initialized when the latter
    ///      reads from storage. Reversing the order causes a panic(0x11) inside getVirtualTestnets.
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

        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        rheoImplementation = vm.envAddress("RHEO_IMPLEMENTATION");
        vaultImplementation = vm.envAddress("VAULT_IMPLEMENTATION");
        collectionsManager = ICollectionsManager(vm.envAddress("COLLECTIONS_MANAGER"));

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address[] memory targets, bytes[] memory datas) = _buildCalls();

        // Push the batched proposal to the Safe API (one signing ceremony covers all 3 setters)
        safe.proposeTransactions(targets, datas, signer, derivationPath);

        // Simulate on Tenderly: override Safe threshold to 1 so a single-signer simulation can execute
        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-phase1.2-wire-factory-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionsData(targets, datas, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }

    /// @notice Prints the calldata for the three setters and the batched delegateCall to
    ///         MultiSendCallOnly. Skips Ledger, Tenderly, and the Safe API entirely — use this
    ///         when you want to build the Safe tx manually in the Safe Web UI.
    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        // safe.initialize() populates the chainId → MultiSendCallOnly address map used below
        address ownerEnv = vm.envAddress("OWNER");
        // F6: defense against .env typo that would sign from a non-canonical Safe.
        require(
            ownerEnv == contracts[block.chainid][Contract.RHEO_GOVERNANCE],
            "OWNER must equal contracts[ARBITRUM_MAINNET][RHEO_GOVERNANCE]"
        );
        safe.initialize(ownerEnv);

        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        rheoImplementation = vm.envAddress("RHEO_IMPLEMENTATION");
        vaultImplementation = vm.envAddress("VAULT_IMPLEMENTATION");
        collectionsManager = ICollectionsManager(vm.envAddress("COLLECTIONS_MANAGER"));

        (address[] memory targets, bytes[] memory datas) = _buildCalls();

        console.log("==============================================================================");
        console.log("OPTION A: Three separate transactions (Safe UI > New transaction > Contract interaction)");
        console.log("          For each, Operation = Call");
        console.log("==============================================================================");
        string[3] memory labels = [
            "setRheoImplementation",
            "setNonTransferrableRebasingTokenVaultImplementation",
            "setCollectionsManager"
        ];
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

        targets[0] = address(sizeFactory);
        datas[0] = abi.encodeCall(SizeFactory.setRheoImplementation, (rheoImplementation));

        targets[1] = address(sizeFactory);
        datas[1] =
            abi.encodeCall(SizeFactory.setNonTransferrableRebasingTokenVaultImplementation, (vaultImplementation));

        targets[2] = address(sizeFactory);
        datas[2] = abi.encodeCall(SizeFactory.setCollectionsManager, (collectionsManager));
    }
}
