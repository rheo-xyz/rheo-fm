// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {PriceFeed} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {IRheoFactoryOffchainGetters} from "@rheo-fm/src/factory/interfaces/IRheoFactoryOffchainGetters.sol";
import {IPriceFeedV1_5_2} from "@rheo-fm/src/oracle/v1.5.2/IPriceFeedV1_5_2.sol";

import {RheoFactoryStorage} from "@rheo-fm/src/factory/RheoFactoryStorage.sol";
import {ActionsBitmap, Authorization} from "@rheo-fm/src/factory/libraries/Authorization.sol";

import {VERSION} from "@rheo-fm/src/market/interfaces/IRheo.sol";

/// @title RheoFactoryOffchainGetters
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice See the documentation in {IRheoFactory}.
abstract contract RheoFactoryOffchainGetters is IRheoFactoryOffchainGetters, RheoFactoryStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IRheoFactoryOffchainGetters
    function getMarket(uint256 index) external view returns (IRheo) {
        return IRheo(markets.at(index));
    }

    /// @inheritdoc IRheoFactoryOffchainGetters
    function getMarketsCount() external view returns (uint256) {
        return markets.length();
    }

    /// @inheritdoc IRheoFactoryOffchainGetters
    function getMarkets() external view returns (IRheo[] memory _markets) {
        _markets = new IRheo[](markets.length());
        for (uint256 i = 0; i < _markets.length; i++) {
            _markets[i] = IRheo(markets.at(i));
        }
    }

    /// @inheritdoc IRheoFactoryOffchainGetters
    function getMarketDescriptions() external view returns (string[] memory descriptions) {
        descriptions = new string[](markets.length());
        // slither-disable-start calls-loop
        for (uint256 i = 0; i < descriptions.length; i++) {
            IRheo size = IRheo(markets.at(i));
            uint256 crLiquidationPercent = Math.mulDivDown(100, size.riskConfig().crLiquidation, PERCENT);
            descriptions[i] = string.concat(
                "Rheo | ",
                size.data().underlyingCollateralToken.symbol(),
                " | ",
                size.data().underlyingBorrowToken.symbol(),
                " | ",
                Strings.toString(crLiquidationPercent),
                " | ",
                size.version()
            );
        }
        // slither-disable-end calls-loop
    }

    /// @inheritdoc IRheoFactoryOffchainGetters
    function isAuthorizedAll(address operator, address onBehalfOf, ActionsBitmap actionsBitmap)
        external
        view
        returns (bool)
    {
        if (operator == onBehalfOf) {
            return true;
        } else {
            uint256 nonce = authorizationNonces[onBehalfOf];
            ActionsBitmap authorizationsActionsBitmap = authorizations[nonce][operator][onBehalfOf];
            return Authorization.toUint256(authorizationsActionsBitmap) & Authorization.toUint256(actionsBitmap)
                == Authorization.toUint256(actionsBitmap);
        }
    }

    /// @inheritdoc IRheoFactoryOffchainGetters
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
