// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 1.2: deploys the three implementations + the CollectionsManager proxy that the
///         live Arbitrum SizeFactory needs before it can mint markets or borrow vaults.
/// @dev    Broadcast as the deployer EOA. None of these calls require admin role on the factory —
///         the wiring (the three setters that DO require admin) is proposed via the Safe in
///         the companion script `ProposeSafeTxWireRheoArbitrumFactory.s.sol`.
///
///         Run:
///           forge script script/DeployRheoArbitrumImplementations.s.sol \
///             --rpc-url arbitrum-production \
///             --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
///             --ffi --verify --broadcast -vvv
///
///         Capture the four addresses from the logs and export RHEO_IMPLEMENTATION,
///         VAULT_IMPLEMENTATION, and COLLECTIONS_MANAGER before running the wiring script.
contract DeployRheoArbitrumImplementationsScript is BaseScript, Networks {
    function run() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        ISizeFactory sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        vm.startBroadcast();

        Rheo rheoImplementation = new Rheo();
        NonTransferrableRebasingTokenVault vaultImplementation = new NonTransferrableRebasingTokenVault();
        CollectionsManager collectionsManagerImplementation = new CollectionsManager();
        ERC1967Proxy collectionsManagerProxy = new ERC1967Proxy(
            address(collectionsManagerImplementation), abi.encodeCall(CollectionsManager.initialize, (sizeFactory))
        );

        vm.stopBroadcast();

        console.log("[Phase 1.2] SizeFactory                          (existing)", address(sizeFactory));
        console.log("[Phase 1.2] Rheo implementation                  (new)     ", address(rheoImplementation));
        console.log("[Phase 1.2] NonTransferrableRebasingTokenVault   (new)     ", address(vaultImplementation));
        console.log(
            "[Phase 1.2] CollectionsManager implementation    (new)     ", address(collectionsManagerImplementation)
        );
        console.log("[Phase 1.2] CollectionsManager proxy             (new)     ", address(collectionsManagerProxy));
        console.log("");
        console.log("Next: export the three addresses below and run ProposeSafeTxWireRheoArbitrumFactory.s.sol");
        console.log("  export RHEO_IMPLEMENTATION=", address(rheoImplementation));
        console.log("  export VAULT_IMPLEMENTATION=", address(vaultImplementation));
        console.log("  export COLLECTIONS_MANAGER=", address(collectionsManagerProxy));
    }
}
