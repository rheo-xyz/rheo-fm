// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

abstract contract BaseScript is Script {
    using Safe for *;
    using Tenderly for *;

    Safe.Client safe;
    Tenderly.Client tenderly;

    error InvalidChainId(uint256 chainid);
    error InvalidPrivateKey(string privateKey);

    string constant TEST_MNEMONIC = "test test test test test test test test test test test junk";
    string constant TEST_NETWORK_CONFIGURATION = "anvil";

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    modifier ignoreGas() {
        vm.pauseGasMetering();
        _;
        vm.resumeGasMetering();
    }

    modifier deleteVirtualTestnets() {
        Tenderly.VirtualTestnet[] memory vnets = tenderly.getVirtualTestnets();
        for (uint256 i = 0; i < vnets.length; i++) {
            tenderly.deleteVirtualTestnetById(vnets[i].id);
        }
        _;
    }

    function getCommitHash() internal returns (string memory) {
        string[] memory inputs = new string[](4);

        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "--short";
        inputs[3] = "HEAD";

        bytes memory res = vm.ffi(inputs);
        return string(res);
    }

    function price(IPriceFeed priceFeed) internal view returns (string memory) {
        return format(priceFeed.getPrice(), priceFeed.decimals(), 2);
    }

    /// @dev returns XXX_XXX_XXX.dd, for example if value is 112307802362740077885500 and decimals is 18, it returns 112_307.80
    function format(uint256 value, uint256 decimals, uint256 precision) internal pure returns (string memory) {
        // Calculate the divisor to get the integer part
        uint256 divisor = 10 ** decimals;
        uint256 integerPart = value / divisor;
        uint256 fractionalPart = value % divisor;

        // Convert integer part to string with thousand separators
        string memory integerStr = _addThousandSeparators(integerPart);

        // Convert fractional part to 2 decimal places
        uint256 scaledFractional = (fractionalPart * (10 ** precision)) / divisor;

        // Format fractional part to always show precision digits
        string memory fractionalStr;
        if (scaledFractional < 10) {
            fractionalStr = string(abi.encodePacked("0", vm.toString(scaledFractional)));
        } else {
            fractionalStr = vm.toString(scaledFractional);
        }

        return string(abi.encodePacked(integerStr, ".", fractionalStr));
    }

    function _addThousandSeparators(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        string memory result = "";
        uint256 count = 0;

        while (value > 0) {
            if (count > 0 && count % 3 == 0) {
                result = string(abi.encodePacked("_", result));
            }

            uint256 digit = value % 10;
            result = string(abi.encodePacked(vm.toString(digit), result));
            value /= 10;
            count++;
        }

        return result;
    }

    function _getMarket(
        ISizeFactory sizeFactory,
        string memory underlyingCollateralTokenSymbol,
        string memory underlyingBorrowTokenSymbol
    ) internal view returns (IRheo market) {
        address[] memory markets = sizeFactory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            IRheo candidate = IRheo(markets[i]);
            if (
                Strings.equal(candidate.data().underlyingCollateralToken.symbol(), underlyingCollateralTokenSymbol)
                    && Strings.equal(candidate.data().underlyingBorrowToken.symbol(), underlyingBorrowTokenSymbol)
            ) {
                return candidate;
            }
        }
        revert("market not found");
    }
}
