// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {PauseAll} from "@rheo-fm/src/protection/PauseAll.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 7 — deploys the `PauseAll` kill-switch contract on Arbitrum mainnet, owned by the
///         governance Safe. The Safe can later transfer ownership to an autonomous monitor (e.g.
///         Hypernative bot) via Ownable2Step's two-step flow once Hypernative integration is
///         validated.
///
/// @dev    EOA broadcast. No admin role needed for the deploy itself — Phase 8 is the Safe tx
///         that grants `PAUSER_ROLE` on the factory to this contract.
///
///         Run:
///           forge script script/DeployPauseAllArbitrum.s.sol \
///             --rpc-url arbitrum-production \
///             --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
///             --ffi --verify --broadcast -vvv
contract DeployPauseAllArbitrumScript is BaseScript, Networks {
    function run() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        ISizeFactory sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        address owner = contracts[block.chainid][Contract.RHEO_GOVERNANCE];
        require(owner != address(0), "RHEO_GOVERNANCE not set in Networks.sol for Arbitrum");

        vm.startBroadcast();
        PauseAll pauseAll = new PauseAll(sizeFactory, owner);
        vm.stopBroadcast();

        console.log("[Phase 7] PauseAll (new)", address(pauseAll));
        console.log("[Phase 7] SizeFactory (wired)", address(pauseAll.sizeFactory()));
        console.log("[Phase 7] Owner (the governance Safe)", pauseAll.owner());
        console.log("");
        console.log("Next:");
        console.log("  1. Commit the address to Networks.sol under Contract.RHEO_PAUSE_ALL.");
        console.log("  2. Export PAUSE_ALL and run ProposeSafeTxGrantPauserRoleToPauseAllArbitrum.s.sol.");
        console.log("  export PAUSE_ALL=", address(pauseAll));
    }
}
