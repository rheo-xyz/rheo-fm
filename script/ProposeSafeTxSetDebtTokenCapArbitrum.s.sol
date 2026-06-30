// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Proposes a Safe transaction calling
///         `market.updateConfig({key: "debtTokenCap", value: 2_000_000e6})` on the Arbitrum
///         WETH/USDC market.
///
///         `debtTokenCap` defaults to `type(uint256).max` at market init (per
///         `src/market/libraries/actions/Initialize.sol:287`), i.e. uncapped. Setting it to
///         $2M USDC limits maximum borrow exposure during the launch period; the team can lift
///         the cap later via another Safe ceremony.
///
/// @dev    Two entry points:
///           - `run()` — Ledger + Tenderly path. Requires SIGNER, LEDGER_PATH, OWNER, MARKET,
///             TENDERLY_*.
///           - `printCalldata()` — manual Safe-UI path. Requires only OWNER + MARKET.
///
///         Run:
///           forge script script/ProposeSafeTxSetDebtTokenCapArbitrum.s.sol \
///             --rpc-url arbitrum-production --sig "printCalldata()" -vvv
contract ProposeSafeTxSetDebtTokenCapArbitrumScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    /// $2,000,000 in USDC (6 decimals) = 2_000_000 * 10**6 = 2e12.
    uint256 internal constant DEBT_TOKEN_CAP = 2_000_000 * 10 ** 6;

    address private signer;
    string private derivationPath;
    address private market;

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

        market = vm.envAddress("MARKET");
        require(market.code.length > 0, "MARKET has no code at given address");

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address target, bytes memory data) = _buildCall();
        safe.proposeTransaction(target, data, signer, derivationPath);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-set-debt-token-cap-vnet", block.chainid);
        bytes memory execTxData = safe.getExecTransactionData(target, data, signer, derivationPath);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTxData);
    }

    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);
        market = vm.envAddress("MARKET");
        require(market.code.length > 0, "MARKET has no code at given address");

        (address target, bytes memory data) = _buildCall();

        console.log("==============================================================================");
        console.log("Safe Transaction Builder input - set debtTokenCap on Rheo Arbitrum WETH/USDC");
        console.log("  debtTokenCap = %s  (= 2,000,000 USDC, 6 decimals)", DEBT_TOKEN_CAP);
        console.log("  One transaction. Operation = Call (0). msg.value = 0.");
        console.log("==============================================================================");
        console.log("");
        console.log("  To (target address):");
        console.log("    %s", target);
        console.log("  Value (wei):");
        console.log("    0");
        console.log("  Operation:");
        console.log("    Call (0)");
        console.log("  Data (hex calldata):");
        console.logBytes(data);
        console.log("");
        console.log("  Decodes to: updateConfig((string,uint256)) key=debtTokenCap value=%s", DEBT_TOKEN_CAP);
        console.log("==============================================================================");
    }

    function _buildCall() private view returns (address target, bytes memory data) {
        target = market;
        data = abi.encodeCall(
            IRheoAdmin.updateConfig, (UpdateConfigParams({key: "debtTokenCap", value: DEBT_TOKEN_CAP}))
        );
    }
}
