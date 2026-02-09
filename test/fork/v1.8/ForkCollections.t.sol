// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";
import {console} from "forge-std/console.sol";

import {RheoMock} from "@rheo-fm/test/mocks/RheoMock.sol";
import {USDC} from "@rheo-fm/test/mocks/USDC.sol";
import {WETH} from "@rheo-fm/test/mocks/WETH.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626Morpho} from "@rheo-fm/test/fork/v1.8/interfaces/IERC4626Morpho.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {
    SellCreditMarketOnBehalfOfParams,
    SellCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {ICollectionsManagerView} from "@rheo-fm/src/collections/interfaces/ICollectionsManagerView.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ProposeSafeTxUpgradeToV1_8_1Script} from "@rheo-fm/script/ProposeSafeTxUpgradeToV1_8_1.s.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

contract ForkCollectionsTest is ForkTest, Networks {
    address[] users;
    IRheo[] collectionMarkets;
    address curator;
    address rateProvider;

    uint256[][] usersPreviousLoanAPRsPerCollectionMarket;

    uint256 tenor = 30 days;
    uint256 collectionId = 0;

    function setUp() public override(ForkTest) {
        vm.createSelectFork("base_archive");
        // 2025-10-21 14h10 UTC
        vm.rollFork(37133235);

        sizeFactory = importRheoFactory("base-production-rheo-factory");
        size = RheoMock(address(sizeFactory.getMarket(0)));
        usdc = USDC(address(size.data().underlyingBorrowToken));
        weth = WETH(payable(address(size.data().underlyingCollateralToken)));
        variablePool = size.data().variablePool;
        owner = Networks.contracts[block.chainid][Contract.RHEO_GOVERNANCE];

        users = new address[](2);
        users[0] = 0x87CDad83a779D785A729a91dBb9FE0DB8be14b3b;
        users[1] = 0x000000f840D8A851718d7DC470bFf1ed09F69107;

        curator = makeAddr("curator");
        rateProvider = 0x39EB0e1039732d8d2380B682Bc00Ad07b864F176;

        _labels();
    }

    function testFork_ForkCollections_v1_8_1() public {
        vm.createSelectFork("base_archive");

        _upgradeToV1_8_1();

        CopyLimitOrderConfig memory loanOfferConfig =
            CopyLimitOrderConfig({minTenor: 30 days, maxTenor: 90 days, minAPR: 0.05e18, maxAPR: 0.1e18, offsetAPR: 0});

        CopyLimitOrderConfig memory borrowOfferConfig = CopyLimitOrderConfig({
            minTenor: 60 days,
            maxTenor: 120 days,
            minAPR: 0.02e18,
            maxAPR: 0.05e18,
            offsetAPR: -0.01e18
        });

        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, loanOfferConfig, borrowOfferConfig);

        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyLoanOfferConfig(alice, collectionId).minTenor,
            loanOfferConfig.minTenor
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyLoanOfferConfig(alice, collectionId).maxTenor,
            loanOfferConfig.maxTenor
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyLoanOfferConfig(alice, collectionId).minAPR,
            loanOfferConfig.minAPR
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyLoanOfferConfig(alice, collectionId).maxAPR,
            loanOfferConfig.maxAPR
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyLoanOfferConfig(alice, collectionId).offsetAPR,
            loanOfferConfig.offsetAPR
        );

        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyBorrowOfferConfig(alice, collectionId).minTenor,
            borrowOfferConfig.minTenor
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyBorrowOfferConfig(alice, collectionId).maxTenor,
            borrowOfferConfig.maxTenor
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyBorrowOfferConfig(alice, collectionId).minAPR,
            borrowOfferConfig.minAPR
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyBorrowOfferConfig(alice, collectionId).maxAPR,
            borrowOfferConfig.maxAPR
        );
        assertEq(
            sizeFactory.collectionsManager().getUserDefinedCollectionCopyBorrowOfferConfig(alice, collectionId)
                .offsetAPR,
            borrowOfferConfig.offsetAPR
        );
    }

    function _upgradeToV1_8_1() internal {
        ProposeSafeTxUpgradeToV1_8_1Script proposeSafeTxUpgradeToV1_8_1Script = new ProposeSafeTxUpgradeToV1_8_1Script();

        (address[] memory targets, bytes[] memory datas) = proposeSafeTxUpgradeToV1_8_1Script.getUpgradeToV1_8_1Data();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
