// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {ISizeFactory, PAUSER_ROLE} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 8 — Safe grants `PAUSER_ROLE` on the SizeFactory to the PauseAll contract so
///         it can call `pause()` on every market via the role-fallback mechanism in
///         `Rheo.pause()`'s `onlyRoleOrRheoFactoryHasRole(PAUSER_ROLE)` modifier.
///
/// @dev    Two entry points:
///           - `run()` — Ledger + Tenderly path.
///             Requires SIGNER, LEDGER_PATH, OWNER, PAUSE_ALL, TENDERLY_*.
///           - `printCalldata()` — manual Safe-UI path. Requires only OWNER + PAUSE_ALL.
///
///         Run:
///           forge script script/ProposeSafeTxGrantPauserRoleToPauseAllArbitrum.s.sol \
///             --rpc-url arbitrum-production --sig "printCalldata()" -vvv
contract ProposeSafeTxGrantPauserRoleToPauseAllArbitrumScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    address private signer;
    string private derivationPath;
    ISizeFactory private sizeFactory;
    address private pauseAll;

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

        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        pauseAll = vm.envAddress("PAUSE_ALL");
        require(pauseAll.code.length > 0, "PAUSE_ALL has no code at given address");

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address target, bytes memory data) = _buildCall();

        safe.proposeTransaction(target, data, signer, derivationPath);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-phase8-grant-pauser-role-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionData(target, data, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }

    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);
        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");
        pauseAll = vm.envAddress("PAUSE_ALL");
        require(pauseAll.code.length > 0, "PAUSE_ALL has no code at given address");

        (address target, bytes memory data) = _buildCall();

        console.log("==============================================================================");
        console.log("Phase 8: SizeFactory.grantRole(PAUSER_ROLE, PauseAll)");
        console.log("         One transaction. Operation = Call");
        console.log("==============================================================================");
        console.log("");
        console.log("  To:        %s   (SizeFactory)", target);
        console.log("  Value:     0");
        console.log("  Operation: Call");
        console.log("  Data:");
        console.logBytes(data);
        console.log("");
        console.log("PAUSER_ROLE = keccak256(\"PAUSER_ROLE\") = 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a");
    }

    function _buildCall() private view returns (address target, bytes memory data) {
        target = address(sizeFactory);
        data = abi.encodeCall(AccessControlUpgradeable.grantRole, (PAUSER_ROLE, pauseAll));
    }
}
