// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Networks} from "@rheo-fm/script/Networks.sol";

import {ChainlinkPriceFeed} from "@rheo-fm/src/oracle/adapters/ChainlinkPriceFeed.sol";
import {ChainlinkSequencerUptimeFeed} from "@rheo-fm/src/oracle/adapters/ChainlinkSequencerUptimeFeed.sol";
import {UniswapV3PriceFeed} from "@rheo-fm/src/oracle/adapters/UniswapV3PriceFeed.sol";
import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @notice F10 — verifies the three sub-contracts created by the v1.5.1 `PriceFeed` constructor
///         on Arbiscan. `forge --verify` on the Phase 3 deploy only verifies the top-level
///         `PriceFeed`; the three sub-contracts (`ChainlinkSequencerUptimeFeed`,
///         `ChainlinkPriceFeed`, `UniswapV3PriceFeed`) ship as unverified bytecode unless this
///         follow-up runs.
///
/// @dev    Self-contained: reads the live PriceFeed at PRICE_FEED, derives each sub-contract's
///         deployed address + constructor args from its immutable public getters, and invokes
///         `forge verify-contract` via vm.ffi.
///
///         Required env vars:
///           - PRICE_FEED          deployed via DeployPriceFeedArbitrum.s.sol
///           - API_KEY_ARBISCAN    Arbiscan API key for the verification calls
///
///         Run (only needs --ffi, no broadcast):
///           forge script script/VerifyPriceFeedSubcontractsArbitrum.s.sol \
///             --rpc-url arbitrum-production --sig "run()" --ffi -vvv
///
///         The script first prints all three forge verify-contract commands (so reviewers can
///         see exactly what's being submitted), then actually executes them.
contract VerifyPriceFeedSubcontractsArbitrumScript is BaseScript, Networks {
    function run() external {
        if (block.chainid != ARBITRUM_MAINNET) revert InvalidChainId(block.chainid);

        PriceFeed pf = PriceFeed(vm.envAddress("PRICE_FEED"));

        ChainlinkSequencerUptimeFeed seq = pf.chainlinkSequencerUptimeFeed();
        ChainlinkPriceFeed clp = pf.chainlinkPriceFeed();
        UniswapV3PriceFeed unif = pf.uniswapV3PriceFeed();

        console.log("==============================================================================");
        console.log("Verifying three PriceFeed sub-contracts on Arbiscan");
        console.log("Parent PriceFeed:", address(pf));
        console.log("==============================================================================");

        _verify(
            address(seq),
            "src/oracle/adapters/ChainlinkSequencerUptimeFeed.sol:ChainlinkSequencerUptimeFeed",
            _abiEncodeSequencer(seq)
        );

        _verify(
            address(clp), "src/oracle/adapters/ChainlinkPriceFeed.sol:ChainlinkPriceFeed", _abiEncodeChainlink(clp)
        );

        _verify(
            address(unif), "src/oracle/adapters/UniswapV3PriceFeed.sol:UniswapV3PriceFeed", _abiEncodeUniswap(unif)
        );

        console.log("");
        console.log("Done. Check Arbiscan to confirm each sub-contract is now marked Verified.");
    }

    function _verify(address contractAddress, string memory contractPath, bytes memory constructorArgs) private {
        string memory argsHex = _bytesToHex(constructorArgs);

        console.log("");
        console.log("Verifying %s at %s", contractPath, contractAddress);
        console.log("  constructor-args: 0x%s", argsHex);

        string[] memory cmd = new string[](11);
        cmd[0] = "forge";
        cmd[1] = "verify-contract";
        cmd[2] = vm.toString(contractAddress);
        cmd[3] = contractPath;
        cmd[4] = "--chain";
        cmd[5] = "42161";
        cmd[6] = "--etherscan-api-key";
        cmd[7] = vm.envString("API_KEY_ARBISCAN");
        cmd[8] = "--constructor-args";
        cmd[9] = string.concat("0x", argsHex);
        cmd[10] = "--watch";

        bytes memory out = vm.ffi(cmd);
        console.log(string(out));
    }

    function _abiEncodeSequencer(ChainlinkSequencerUptimeFeed seq) private view returns (bytes memory) {
        // constructor(AggregatorV3Interface _sequencerUptimeFeed)
        return abi.encode(seq.sequencerUptimeFeed());
    }

    function _abiEncodeChainlink(ChainlinkPriceFeed clp) private view returns (bytes memory) {
        // constructor(
        //   uint256 _decimals,
        //   AggregatorV3Interface _baseAggregator,
        //   AggregatorV3Interface _quoteAggregator,
        //   uint256 _baseStalePriceInterval,
        //   uint256 _quoteStalePriceInterval
        // )
        return abi.encode(
            clp.decimals(),
            clp.baseAggregator(),
            clp.quoteAggregator(),
            clp.baseStalePriceInterval(),
            clp.quoteStalePriceInterval()
        );
    }

    function _abiEncodeUniswap(UniswapV3PriceFeed unif) private view returns (bytes memory) {
        // constructor(
        //   uint256 _decimals,
        //   IERC20Metadata _baseToken,
        //   IERC20Metadata _quoteToken,
        //   IUniswapV3Pool _uniswapV3Pool,
        //   uint32 _twapWindow,
        //   uint32 _averageBlockTime
        // )
        return abi.encode(
            unif.decimals(),
            unif.baseToken(),
            unif.quoteToken(),
            unif.uniswapV3Pool(),
            unif.twapWindow(),
            unif.averageBlockTime()
        );
    }

    /// @dev Convert `bytes` → lowercase hex without the leading 0x.
    function _bytesToHex(bytes memory data) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            out[2 * i] = alphabet[uint8(data[i]) >> 4];
            out[2 * i + 1] = alphabet[uint8(data[i]) & 0xf];
        }
        return string(out);
    }
}
