// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {ReserveConfiguration} from "@aave/protocol/libraries/configuration/ReserveConfiguration.sol";
import {DataTypes} from "@aave/protocol/libraries/types/DataTypes.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 2a — proposes a Safe transaction calling
///         `sizeFactory.createBorrowTokenVault(aavePool, USDC)` on the live Arbitrum factory.
///         This is admin-only on the factory, so it has to go through the Safe.
///
/// @dev    Two entry points:
///           - `run()` — pushes the proposal via Ledger + creates a Tenderly vnet for simulation.
///             Requires SIGNER, LEDGER_PATH, OWNER, TENDERLY_ACCOUNT_NAME, TENDERLY_PROJECT_NAME,
///             TENDERLY_ACCESS_KEY.
///             Run:
///               forge script script/ProposeSafeTxCreateBorrowVaultArbitrum.s.sol \
///                 --rpc-url arbitrum-production --sender $SIGNER --account $DEPLOYER_ACCOUNT --ffi -vvv
///
///           - `printCalldata()` — prints the raw transaction payload so you can build it manually
///             in the Safe Web UI. No Ledger, no Tenderly, no Safe API. Requires only OWNER.
///             Run:
///               forge script script/ProposeSafeTxCreateBorrowVaultArbitrum.s.sol \
///                 --rpc-url arbitrum-production --sig "printCalldata()" -vvv
///
///         After execution, the SizeFactory emits `CreateBorrowTokenVault(address)` — grab the
///         vault address from that event log and export it as BORROW_TOKEN_VAULT for Phase 2b.
contract ProposeSafeTxCreateBorrowVaultArbitrumScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address private signer;
    string private derivationPath;
    ISizeFactory private sizeFactory;
    NetworkConfiguration private cfg;

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
        cfg = params("arbitrum-production-weth-usdc");

        _runPreflightChecks();

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address target, bytes memory data) = _buildCall();

        safe.proposeTransaction(target, data, signer, derivationPath);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-phase2a-create-borrow-vault-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionData(target, data, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }

    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");
        cfg = params("arbitrum-production-weth-usdc");

        _runPreflightChecks();

        (address target, bytes memory data) = _buildCall();

        console.log("==============================================================================");
        console.log("Phase 2a: SizeFactory.createBorrowTokenVault(aavePool, USDC)");
        console.log("          One transaction. Operation = Call");
        console.log("==============================================================================");
        console.log("");
        console.log("  To:        %s", target);
        console.log("  Value:     0");
        console.log("  Operation: Call");
        console.log("  Data:");
        console.logBytes(data);
        console.log("");
        console.log("After execution, grab BORROW_TOKEN_VAULT from the CreateBorrowTokenVault event.");
    }

    function _buildCall() private view returns (address target, bytes memory data) {
        target = address(sizeFactory);
        data = abi.encodeCall(
            ISizeFactory.createBorrowTokenVault, (IPool(cfg.variablePool), IERC20Metadata(cfg.underlyingBorrowToken))
        );
    }

    /// @dev F8 + F9 pre-flight checks. View-only — runs in both `run()` and `printCalldata()` so the
    ///      Safe ceremony refuses to even proceed if the underlying assumptions are wrong.
    function _runPreflightChecks() private view {
        // F9: refuse to propose if a borrow vault is already tracked for this chain.
        // SizeFactory itself does NOT enforce uniqueness on (variablePool, underlyingToken), so the
        // guard lives here. After Phase 2a executes, commit the new vault address to
        // `contracts[ARBITRUM_MAINNET][Contract.RHEO_BORROW_VAULT_USDC]` in Networks.sol so a
        // double-ceremony cannot accidentally spin up a second canonical vault.
        require(
            contracts[block.chainid][Contract.RHEO_BORROW_VAULT_USDC] == address(0),
            "RHEO_BORROW_VAULT_USDC already set in Networks.sol; refusing to create another"
        );

        // F8: Aave v3 USDC reserve health. Catches the "governance changed config between dev and
        // prod" footgun where a frozen/paused reserve would silently break user deposits.
        DataTypes.ReserveData memory r = IPool(cfg.variablePool).getReserveData(cfg.underlyingBorrowToken);
        require(r.configuration.getActive(), "Aave USDC reserve is inactive");
        require(!r.configuration.getPaused(), "Aave USDC reserve is paused");
        require(!r.configuration.getFrozen(), "Aave USDC reserve is frozen");
        require(r.aTokenAddress != address(0), "Aave USDC reserve has no aToken");
    }
}
