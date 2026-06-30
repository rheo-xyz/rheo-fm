// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Phase 5.5 — proposes a Safe transaction that calls
///         `market.updateConfig({key:"overdueLiquidationRewardPercent", value: 0.01e18})` on the
///         freshly-created Arbitrum WETH/USDC market.
///
///         Why: `overdueLiquidationRewardPercent` is the only fee-config-shaped parameter that
///         is NOT settable via `InitializeFeeConfigParams`. At market creation it defaults to
///         `state.feeConfig.liquidationRewardPercent` (= 0.05e18, 5 %), which mirrors the
///         underwater-liquidation reward. We tighten it to 1 % at launch so liquidators have a
///         clear-but-modest incentive to close just-overdue solvent loans — matches the value
///         used in the team's `test/local/actions/Liquidate.t.sol` fixtures.
///
/// @dev    Two entry points (same pattern as the other Safe-tx scripts):
///           - `run()` — pushes the proposal via Ledger + creates a Tenderly vnet for simulation.
///             Requires SIGNER, LEDGER_PATH, OWNER, MARKET, TENDERLY_*.
///           - `printCalldata()` — prints the raw transaction payload for manual Safe-UI building.
///             Requires only MARKET + OWNER.
///
///         Run:
///           forge script script/ProposeSafeTxSetInitialMarketConfigArbitrum.s.sol \
///             --rpc-url arbitrum-production --sig "printCalldata()" -vvv
contract ProposeSafeTxSetInitialMarketConfigArbitrumScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    /// 0.01e18 = 1 %. Matches the value baked into Liquidate.t.sol:223 and is one tenth of the
    /// default-via-init (5 %). Reduces the liquidation reward for OVERDUE-but-still-solvent loans
    /// while leaving the underwater-liquidation reward (`liquidationRewardPercent`) unchanged.
    uint256 internal constant OVERDUE_LIQUIDATION_REWARD_PERCENT = 0.01e18;

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
            tenderly.createVirtualTestnet("arbitrum-phase5.5-set-initial-config-vnet", block.chainid);
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
        console.log("Phase 5.5: market.updateConfig(\"overdueLiquidationRewardPercent\", 0.01e18)");
        console.log("           One transaction. Operation = Call");
        console.log("==============================================================================");
        console.log("");
        console.log("  To:        %s   (the Arbitrum WETH/USDC market)", target);
        console.log("  Value:     0");
        console.log("  Operation: Call");
        console.log("  Data:");
        console.logBytes(data);
        console.log("");
    }

    function _buildCall() private view returns (address target, bytes memory data) {
        target = market;
        data = abi.encodeCall(
            IRheoAdmin.updateConfig,
            (UpdateConfigParams({key: "overdueLiquidationRewardPercent", value: OVERDUE_LIQUIDATION_REWARD_PERCENT}))
        );
    }
}
