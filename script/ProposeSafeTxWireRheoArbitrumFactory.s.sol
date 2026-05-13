// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

/// @notice Phase 1.2 wiring: proposes a single Safe transaction (delegateCall to MultiSendCallOnly)
///         that batches the three admin-only setters needed to make the SizeFactory usable.
///
///           - setRheoImplementation(rheoImpl)
///           - setNonTransferrableRebasingTokenVaultImplementation(vaultImpl)
///           - setCollectionsManager(collectionsManagerProxy)
///
/// @dev    Required env vars (in addition to API_KEY_ALCHEMY for the RPC):
///           - SIGNER, LEDGER_PATH                 Safe signer (Ledger)
///           - OWNER                               Safe multisig (0x462B…c3a7)
///           - RHEO_IMPLEMENTATION                 from DeployRheoArbitrumImplementations.s.sol
///           - VAULT_IMPLEMENTATION                from DeployRheoArbitrumImplementations.s.sol
///           - COLLECTIONS_MANAGER                 the proxy (not the impl), from same script
///           - TENDERLY_ACCOUNT_NAME
///           - TENDERLY_PROJECT_NAME
///           - TENDERLY_ACCESS_KEY
///
///         Run:
///           forge script script/ProposeSafeTxWireRheoArbitrumFactory.s.sol \
///             --rpc-url arbitrum-production \
///             --sender $SIGNER --account $DEPLOYER_ACCOUNT \
///             --ffi -vvv
contract ProposeSafeTxWireRheoArbitrumFactoryScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    function run() external deleteVirtualTestnets {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        address signer = vm.envAddress("SIGNER");
        string memory derivationPath = vm.envString("LEDGER_PATH");

        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        safe.initialize(vm.envAddress("OWNER"));

        ISizeFactory sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        address rheoImplementation = vm.envAddress("RHEO_IMPLEMENTATION");
        address vaultImplementation = vm.envAddress("VAULT_IMPLEMENTATION");
        ICollectionsManager collectionsManager = ICollectionsManager(vm.envAddress("COLLECTIONS_MANAGER"));

        address[] memory targets = new address[](3);
        bytes[] memory datas = new bytes[](3);

        targets[0] = address(sizeFactory);
        datas[0] = abi.encodeCall(SizeFactory.setRheoImplementation, (rheoImplementation));

        targets[1] = address(sizeFactory);
        datas[1] =
            abi.encodeCall(SizeFactory.setNonTransferrableRebasingTokenVaultImplementation, (vaultImplementation));

        targets[2] = address(sizeFactory);
        datas[2] = abi.encodeCall(SizeFactory.setCollectionsManager, (collectionsManager));

        // Push the batched proposal to the Safe API (one signing ceremony covers all 3 setters)
        safe.proposeTransactions(targets, datas, signer, derivationPath);

        // Simulate on Tenderly: override Safe threshold to 1 so a single-signer simulation can execute
        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-phase1.2-wire-factory-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionsData(targets, datas, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }
}
