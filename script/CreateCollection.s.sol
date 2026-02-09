// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/Script.sol";

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, NetworkConfiguration, Networks} from "@rheo-fm/script/Networks.sol";

import {ICollectionsManager} from "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

contract CreateCollectionScript is BaseScript, Networks {
    address curator;
    address rateProvider;

    function setUp() public {
        curator = vm.envAddress("CURATOR");
        rateProvider = vm.envAddress("RATE_PROVIDER");
    }

    function run() public broadcast {
        RheoFactory sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        ICollectionsManager collectionsManager = sizeFactory.collectionsManager();
        uint256 collectionId = collectionsManager.createCollection();
        IRheo[] memory markets = sizeFactory.getMarkets();
        IRheo[] memory unpausedMarkets = new IRheo[](markets.length);
        uint256 j = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            if (!PausableUpgradeable(address(markets[i])).paused()) {
                unpausedMarkets[j] = markets[i];
                j++;
            }
        }
        _unsafeSetLength(unpausedMarkets, j);
        collectionsManager.addMarketsToCollection(collectionId, unpausedMarkets);
        address[] memory rateProviders = new address[](1);
        rateProviders[0] = rateProvider;
        for (uint256 i = 0; i < unpausedMarkets.length; i++) {
            collectionsManager.addRateProvidersToCollectionMarket(collectionId, unpausedMarkets[i], rateProviders);
        }
        IERC721(address(collectionsManager)).safeTransferFrom(msg.sender, curator, collectionId);
    }
}
