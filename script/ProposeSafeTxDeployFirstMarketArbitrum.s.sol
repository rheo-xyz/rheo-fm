// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {ISizeFactoryV1_9} from "@rheo-solidity/src/factory/interfaces/ISizeFactoryV1_9.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice Proposes a Safe transaction to create the FIRST WETH/USDC market on Arbitrum mainnet.
/// @dev Run after Phases 1-3 are complete:
///        Phase 1: SizeFactory + CollectionsManager + impls deployed (from `lib/rheo-solidity/script/DeploySizeFactory.s.sol`)
///        Phase 2: BorrowTokenVault for USDC created via `sizeFactory.createBorrowTokenVault(aavePool, usdc)` and adapters wired
///        Phase 3: PriceFeed deployed via `new PriceFeed(params("arbitrum-production-weth-usdc").priceFeedParams)`
///      Before running this script, populate `contracts[ARBITRUM_MAINNET][Contract.RHEO_FACTORY]` in script/Networks.sol.
///      Required env vars:
///        - SIGNER, LEDGER_PATH       Safe signer (Ledger)
///        - OWNER                     Safe multisig address (0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7)
///        - PRICE_FEED                Address from Phase 3
///        - BORROW_TOKEN_VAULT        Address from Phase 2 (svUSDC)
///        - TENDERLY_ACCOUNT_NAME, TENDERLY_PROJECT_NAME, TENDERLY_ACCESS_KEY
///      Invocation:
///        forge script script/ProposeSafeTxDeployFirstMarketArbitrum.s.sol \
///          --rpc-url arbitrum-production --sender $SIGNER --account $DEPLOYER_ACCOUNT --ffi -vvv
contract ProposeSafeTxDeployFirstMarketArbitrumScript is BaseScript, Networks {
    using Tenderly for *;
    using Safe for *;

    /// @dev The Safe multisig is also the protocol fee recipient on Arbitrum.
    address private constant FEE_RECIPIENT = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;

    address signer;
    string derivationPath;

    ISizeFactory private sizeFactory;
    address private safeAddress;
    IPriceFeed private priceFeed;
    address private borrowTokenVault;

    modifier parseEnv() {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");

        string memory accountSlug = vm.envString("TENDERLY_ACCOUNT_NAME");
        string memory projectSlug = vm.envString("TENDERLY_PROJECT_NAME");
        string memory accessKey = vm.envString("TENDERLY_ACCESS_KEY");
        tenderly.initialize(accountSlug, projectSlug, accessKey);

        safeAddress = vm.envAddress("OWNER");
        safe.initialize(safeAddress);

        priceFeed = IPriceFeed(vm.envAddress("PRICE_FEED"));
        borrowTokenVault = vm.envAddress("BORROW_TOKEN_VAULT");

        _;
    }

    function run() external parseEnv deleteVirtualTestnets {
        (address target, bytes memory data) = _buildCall();

        safe.proposeTransaction(target, data, signer, derivationPath);

        Tenderly.VirtualTestnet memory vnet =
            tenderly.createVirtualTestnet("arbitrum-weth-usdc-vnet", block.chainid);
        bytes memory execTransactionData = safe.getExecTransactionData(target, data, signer, derivationPath);
        // Override Safe `threshold` (storage slot 4) to 1 so Tenderly can execute the simulated tx with a single signer.
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(vnet.id, signer, safe.instance().safe, execTransactionData);
    }

    /// @notice Prints the createMarketRheo calldata so the Safe tx can be built manually in the
    ///         Safe Web UI. Skips Ledger, Tenderly, and the Safe API. Requires PRICE_FEED,
    ///         BORROW_TOKEN_VAULT (used to assemble the data) — same env vars as `run()` minus the
    ///         signing-related ones.
    ///         Run:
    ///           forge script script/ProposeSafeTxDeployFirstMarketArbitrum.s.sol \
    ///             --rpc-url arbitrum-production --sig "printCalldata()" -vvv
    function printCalldata() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        sizeFactory = ISizeFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        require(address(sizeFactory) != address(0), "RHEO_FACTORY not set in Networks.sol for Arbitrum");
        priceFeed = IPriceFeed(vm.envAddress("PRICE_FEED"));
        borrowTokenVault = vm.envAddress("BORROW_TOKEN_VAULT");

        (address target, bytes memory data) = _buildCall();

        console.log("==============================================================================");
        console.log("Phase 5: SizeFactory.createMarketRheo(fee, risk, oracle, data)");
        console.log("         One transaction. Operation = Call");
        console.log("==============================================================================");
        console.log("");
        console.log("  To:        %s", target);
        console.log("  Value:     0");
        console.log("  Operation: Call");
        console.log("  Data:");
        console.logBytes(data);
        console.log("");
        console.log("After execution, the market proxy address is in the CreateMarket event log.");
    }

    function _buildCall() private view returns (address target, bytes memory data) {
        NetworkConfiguration memory cfg = params("arbitrum-production-weth-usdc");

        InitializeFeeConfigParams memory feeConfigParams = InitializeFeeConfigParams({
            swapFeeAPR: 0.005e18,
            fragmentationFee: cfg.fragmentationFee,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.01e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: FEE_RECIPIENT
        });

        InitializeRiskConfigParams memory riskConfigParams = InitializeRiskConfigParams({
            crOpening: cfg.crOpening,
            crLiquidation: cfg.crLiquidation,
            minimumCreditBorrowToken: cfg.minimumCreditBorrowToken,
            minTenor: 1 hours,
            maxTenor: 5 * 365 days,
            maturities: _maturities()
        });

        InitializeOracleParams memory oracleParams = InitializeOracleParams({priceFeed: address(priceFeed)});

        InitializeDataParams memory dataParams = InitializeDataParams({
            weth: cfg.weth,
            underlyingCollateralToken: cfg.underlyingCollateralToken,
            underlyingBorrowToken: cfg.underlyingBorrowToken,
            variablePool: cfg.variablePool,
            borrowTokenVault: borrowTokenVault,
            sizeFactory: address(sizeFactory)
        });

        target = address(sizeFactory);
        data = abi.encodeCall(
            ISizeFactoryV1_9.createMarketRheo, (feeConfigParams, riskConfigParams, oracleParams, dataParams)
        );
    }

    /// @dev Quarter-end maturities for the WETH/USDC market launch. Pattern: last Friday of the
    ///      quarter at 08:00 UTC, falling back to the last weekday if the last Friday is a holiday
    ///      (Q4 2026 → 2026-12-31 because Christmas Day fell on the last Friday).
    ///        1782460800 → 2026-06-26 08:00 UTC (Q2 2026 — Friday)
    ///        1790323200 → 2026-09-25 08:00 UTC (Q3 2026 — Friday)
    ///        1798704000 → 2026-12-31 08:00 UTC (Q4 2026 — Thursday, last weekday)
    ///        1806048000 → 2027-03-26 08:00 UTC (Q1 2027 — Friday)
    function _maturities() internal pure returns (uint256[] memory maturities) {
        maturities = new uint256[](4);
        maturities[0] = 1782460800;
        maturities[1] = 1790323200;
        maturities[2] = 1798704000;
        maturities[3] = 1806048000;
    }
}
