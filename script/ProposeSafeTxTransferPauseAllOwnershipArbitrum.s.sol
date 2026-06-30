// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {PauseAll} from "@rheo-fm/src/protection/PauseAll.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 9.2 — Safe initiates a two-step transfer of `PauseAll` ownership to the
///         Hypernative bot. The bot must subsequently call `acceptOwnership()` (Phase 9.3) for
///         the transfer to take effect; until then the Safe remains the owner and ` pauseAll()`
///         continues to be Safe-only. This makes the handoff reversible (Safe can call
///         `transferOwnership(safeAddress)` to cancel before the bot accepts).
///
/// @dev    Two entry points:
///           - `run()` — Ledger + Tenderly. Requires SIGNER, LEDGER_PATH, OWNER, PAUSE_ALL,
///             HYPERNATIVE_BOT, TENDERLY_*.
///           - `printCalldata()` — manual Safe UI. Requires only OWNER, PAUSE_ALL, HYPERNATIVE_BOT.
///             Run:
///               forge script script/ProposeSafeTxTransferPauseAllOwnershipArbitrum.s.sol \
///                 --rpc-url arbitrum-production --sig "printCalldata()" -vvv
contract ProposeSafeTxTransferPauseAllOwnershipArbitrumScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    address private signer;
    string private derivationPath;
    PauseAll private pauseAll;
    address private hypernativeBot;

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
        require(
            ownerEnv == contracts[block.chainid][Contract.RHEO_GOVERNANCE],
            "OWNER must equal contracts[ARBITRUM_MAINNET][RHEO_GOVERNANCE]"
        );
        safe.initialize(ownerEnv);

        _resolveAndValidate(ownerEnv);

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address target, bytes memory data) = _buildCall();

        safe.proposeTransaction(target, data, signer, derivationPath);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-phase9-transfer-pauseall-ownership-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionData(target, data, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }

    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        address expectedSafe = contracts[block.chainid][Contract.RHEO_GOVERNANCE];
        _resolveAndValidate(expectedSafe);

        (address target, bytes memory data) = _buildCall();

        console.log("==============================================================================");
        console.log("Phase 9.2: PauseAll.transferOwnership(hypernativeBot)");
        console.log("           One transaction. Operation = Call");
        console.log("           Reversible: Safe stays owner until bot calls acceptOwnership().");
        console.log("==============================================================================");
        console.log("");
        console.log("  To:        %s   (PauseAll)", target);
        console.log("  Value:     0");
        console.log("  Operation: Call");
        console.log("  Pending owner after exec: %s", hypernativeBot);
        console.log("  Data:");
        console.logBytes(data);
        console.log("");
        console.log("Next: configure Hypernative to have the bot call acceptOwnership() on PauseAll.");
    }

    /// @dev Centralized read + sanity checks so `run()` and `printCalldata()` stay in sync.
    function _resolveAndValidate(address expectedSafe) private {
        address pauseAllAddr = contracts[block.chainid][Contract.RHEO_PAUSE_ALL];
        require(
            pauseAllAddr != address(0),
            "RHEO_PAUSE_ALL not set in Networks.sol - populate after Phase 7 lands on-chain"
        );
        pauseAll = PauseAll(pauseAllAddr);
        require(address(pauseAll).code.length > 0, "PauseAll has no code at registered address");

        // The Safe MUST currently own PauseAll for the transfer to make sense.
        require(
            pauseAll.owner() == expectedSafe,
            "PauseAll.owner() != Safe - ownership has already moved or Phase 7 deployed it differently"
        );

        hypernativeBot = vm.envAddress("HYPERNATIVE_BOT");
        require(hypernativeBot != address(0), "HYPERNATIVE_BOT must be non-zero");
        // Belt-and-suspenders: don't propose a transfer to self — that'd just clear pendingOwner
        // and have no operational effect, wasting a Safe ceremony.
        require(hypernativeBot != expectedSafe, "HYPERNATIVE_BOT must differ from the Safe");
    }

    function _buildCall() private view returns (address target, bytes memory data) {
        target = address(pauseAll);
        data = abi.encodeCall(Ownable2Step.transferOwnership, (hypernativeBot));
    }
}
