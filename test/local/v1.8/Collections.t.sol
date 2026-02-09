// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";

import {ICollectionsManagerView} from "@rheo-fm/src/collections/interfaces/ICollectionsManagerView.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {CopyLimitOrderConfig, FixedMaturityLimitOrder} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {UserCopyLimitOrderConfigs} from "@rheo-fm/src/market/RheoStorage.sol";

import {
    BuyCreditMarketOnBehalfOfParams,
    BuyCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/BuyCreditMarket.sol";

import {
    SellCreditMarketOnBehalfOfParams,
    SellCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";
import {SetCopyLimitOrderConfigsParams} from "@rheo-fm/src/market/libraries/actions/SetCopyLimitOrderConfigs.sol";
import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";

import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {CollectionsManagerBase} from "@rheo-fm/src/collections/CollectionsManagerBase.sol";
import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";
import {RheoMock} from "@rheo-fm/test/mocks/RheoMock.sol";

contract CollectionsTest is BaseTest {
    CopyLimitOrderConfig private nullCopy;
    CopyLimitOrderConfig private noCopy =
        CopyLimitOrderConfig({minTenor: 0, maxTenor: 0, minAPR: 0, maxAPR: 0, offsetAPR: type(int256).max});
    CopyLimitOrderConfig private fullCopy = CopyLimitOrderConfig({
        minTenor: 0,
        maxTenor: type(uint256).max,
        minAPR: 0,
        maxAPR: type(uint256).max,
        offsetAPR: 0
    });

    function setUp() public override {
        super.setUp();
        _deployRheoMarket2();
    }

    function test_Collections_subscribeToCollection_check_APR() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 borrowOfferAPR = size.getUserDefinedBorrowOfferAPR(bob, _maturity(30 days));
        assertEq(borrowOfferAPR, 0.05e18);

        uint256 loanOfferAPR = size.getUserDefinedLoanOfferAPR(bob, _maturity(60 days));
        assertEq(loanOfferAPR, 0.08e18);

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), borrowOfferAPR);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), loanOfferAPR);
    }

    function test_Collections_subscribeToCollection_copy_only_loan_offer() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, fullCopy, noCopy);
        _subscribeToCollection(alice, collectionId);

        vm.expectRevert();
        size.getBorrowOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.12e18));
        assertEq(size.getUserDefinedBorrowOfferAPR(alice, _maturity(30 days)), 0.12e18);

        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);
    }

    function test_Collections_setCopyLimitOrderConfigs_copy_only_borrow_offer() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, noCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.07e18));
        assertEq(size.getUserDefinedLoanOfferAPR(alice, _maturity(60 days)), 0.07e18);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
    }

    function test_Collections_unsubscribeFromCollections_reset_copy() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, fullCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        _unsubscribeFromCollection(alice, collectionId);

        assertEq(collectionsManager.isSubscribedToCollection(alice, collectionId), false);
        assertEq(collectionsManager.isCopyingCollectionMarketRateProvider(alice, collectionId, size, bob), false);

        uint256 borrowMaturity = _maturity(30 days);
        uint256 loanMaturity = _maturity(60 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollectionsManagerView.InvalidCollectionMarketRateProvider.selector,
                collectionId,
                address(size),
                address(bob)
            )
        );
        size.getBorrowOfferAPR(alice, collectionId, bob, borrowMaturity);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollectionsManagerView.InvalidCollectionMarketRateProvider.selector,
                collectionId,
                address(size),
                address(bob)
            )
        );
        size.getLoanOfferAPR(alice, collectionId, bob, loanMaturity);
    }

    function test_Collections_setCopyLimitOrderConfigs_tenor_boundaries() public {
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.03e18), uint256(90 days), uint256(0.12e18)
            )
        );
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.02e18), uint256(120 days), uint256(0.07e18)
            )
        );

        CopyLimitOrderConfig memory copyLoanOfferConfig =
            CopyLimitOrderConfig({minTenor: 60 days, maxTenor: 90 days, minAPR: 0.05e18, maxAPR: 0.1e18, offsetAPR: 0});

        CopyLimitOrderConfig memory copyBorrowOfferConfig =
            CopyLimitOrderConfig({minTenor: 60 days, maxTenor: 90 days, minAPR: 0.01e18, maxAPR: 0.03e18, offsetAPR: 0});

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, copyLoanOfferConfig, copyBorrowOfferConfig);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getUserDefinedLoanOfferAPR(bob, _maturity(30 days)), 0.03e18);
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        assertEq(size.getUserDefinedBorrowOfferAPR(bob, _maturity(120 days)), 0.07e18);
        vm.expectRevert();
        size.getBorrowOfferAPR(alice, collectionId, bob, _invalidMaturityLong());
    }

    function test_Collections_setCopyLimitOrderConfigs_apr_boundaries() public {
        uint256 maturity = block.timestamp + 150 days;
        uint256[] memory maturities = new uint256[](4);
        uint256[] memory aprs = new uint256[](4);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 60 days;
        maturities[2] = block.timestamp + 90 days;
        maturities[3] = block.timestamp + 120 days;
        aprs[0] = 0.03e18;
        aprs[1] = 0.04e18;
        aprs[2] = 0.12e18;
        aprs[3] = 0.15e18;

        _buyCreditLimit(bob, maturity, FixedMaturityLimitOrder({maturities: maturities, aprs: aprs}));
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days), block.timestamp + uint256(60 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.04e18), uint256(0.2e18))
            })
        );

        CopyLimitOrderConfig memory copyLoanOfferConfig =
            CopyLimitOrderConfig({minTenor: 30 days, maxTenor: 90 days, minAPR: 0.1e18, maxAPR: 0.11e18, offsetAPR: 0});

        CopyLimitOrderConfig memory copyBorrowOfferConfig =
            CopyLimitOrderConfig({minTenor: 30 days, maxTenor: 60 days, minAPR: 0.05e18, maxAPR: 0.12e18, offsetAPR: 0});

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, copyLoanOfferConfig, copyBorrowOfferConfig);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getUserDefinedLoanOfferAPR(bob, _maturity(30 days)), 0.03e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.1e18);

        assertEq(size.getUserDefinedLoanOfferAPR(bob, _maturity(90 days)), 0.12e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(90 days)), 0.11e18);

        assertEq(size.getUserDefinedBorrowOfferAPR(bob, _maturity(30 days)), 0.04e18);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);

        assertEq(size.getUserDefinedBorrowOfferAPR(bob, _maturity(60 days)), 0.2e18);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.12e18);
    }

    function test_Collections_setCopyLimitOrderConfigs_loan_offer_scenario() public {
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days),
                    block.timestamp + uint256(120 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.06e18), uint256(0.1e18), uint256(0.14e18))
            })
        );

        CopyLimitOrderConfig memory copyLoanOfferConfig = CopyLimitOrderConfig({
            minTenor: 60 days,
            maxTenor: 120 days,
            minAPR: 0.1e18,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, copyLoanOfferConfig, noCopy);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.1e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(90 days)), 0.1e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(120 days)), 0.14e18);

        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityLong());
    }

    function test_Collections_setCopyLimitOrderConfigs_borrow_offer_scenario() public {
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days),
                    block.timestamp + uint256(120 days),
                    block.timestamp + uint256(150 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(
                    uint256(0.06e18), uint256(0.2e18), uint256(0.2e18), uint256(0.2e18)
                )
            })
        );

        CopyLimitOrderConfig memory copyBorrowOfferConfig =
            CopyLimitOrderConfig({minTenor: 60 days, maxTenor: 120 days, minAPR: 0, maxAPR: 0.1e18, offsetAPR: 0});

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, noCopy, copyBorrowOfferConfig);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.06e18);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(90 days)), 0.1e18);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(120 days)), 0.1e18);

        vm.expectRevert();
        size.getBorrowOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        vm.expectRevert();
        size.getBorrowOfferAPR(alice, collectionId, bob, _invalidMaturityLong());
    }

    function test_Collections_subscribeToCollection_market_order_chooses_rate_provider() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, fullCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.1e18));
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.15e18));

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.06e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.09e18));

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.06e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.09e18);
    }

    function test_Collections_setCopyLimitOrderConfigs_deletes_single_copy() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, fullCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.1e18));

        _setCopyLimitOrderConfigs(alice, noCopy, fullCopy);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
        assertEq(size.getUserDefinedLoanOfferAPR(alice, _maturity(60 days)), 0.1e18);

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.06e18));

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.06e18);
        assertEq(size.getUserDefinedLoanOfferAPR(alice, _maturity(60 days)), 0.1e18);
    }

    function test_Collections_setCopyLimitOrderConfigs_with_offset() public {
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.05e18), uint256(60 days), uint256(0.08e18)
            )
        );
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.07e18), uint256(60 days), uint256(0.18e18)
            )
        );

        CopyLimitOrderConfig memory copyLoanOfferConfig = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0.1e18,
            maxAPR: type(uint256).max,
            offsetAPR: 0.03e18
        });

        CopyLimitOrderConfig memory copyBorrowOfferConfig = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: 0.12e18,
            offsetAPR: -0.01e18
        });

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, copyLoanOfferConfig, copyBorrowOfferConfig);
        _subscribeToCollection(alice, collectionId);

        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.1e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.11e18);

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.06e18);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.12e18);
    }

    function test_Collections_subscribeToCollection_can_leave_inverted_curves_with_offsetAPR() public {
        _deposit(alice, usdc, 1000e6);
        _deposit(candy, weth, 100e18);

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.03e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        CopyLimitOrderConfig memory loanCopy = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: -0.01e18
        });

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, loanCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        uint256 maturity = block.timestamp + 30 days;
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, maturity), 0.03e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, maturity), 0.04e18);

        assertTrue(
            size.getLoanOfferAPR(alice, collectionId, bob, maturity)
                > size.getBorrowOfferAPR(alice, collectionId, bob, maturity)
        );

        vm.prank(candy);
        size.sellCreditMarket(
            SellCreditMarketParams({
                lender: alice,
                creditPositionId: RESERVED_ID,
                amount: 50e6,
                maturity: maturity,
                maxAPR: type(uint256).max,
                deadline: block.timestamp + 150 days,
                exactAmountIn: false,
                collectionId: collectionId,
                rateProvider: bob
            })
        );

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.04e18));

        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, maturity), 0.04e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, maturity), 0.04e18);

        assertTrue(
            !(
                size.getLoanOfferAPR(alice, collectionId, bob, maturity)
                    > size.getBorrowOfferAPR(alice, collectionId, bob, maturity)
            )
        );

        vm.prank(candy);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVERTED_OFFERS.selector, alice, maturity));
        size.sellCreditMarket(
            SellCreditMarketParams({
                lender: alice,
                creditPositionId: RESERVED_ID,
                amount: 50e6,
                maturity: maturity,
                maxAPR: type(uint256).max,
                deadline: block.timestamp + 150 days,
                exactAmountIn: false,
                collectionId: collectionId,
                rateProvider: bob
            })
        );
    }

    function test_Collections_subscribeToCollection_leave_inverted_curves_but_market_orders_revert() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.03e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        CopyLimitOrderConfig memory loanCopy = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: -0.01e18
        });

        _deposit(alice, weth, 1 ether);
        _deposit(alice, usdc, 3000e6);

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, loanCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        uint256 maturity = block.timestamp + 30 days;
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, maturity), 0.03e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, maturity), 0.04e18);

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.04e18));

        _deposit(candy, usdc, 2000e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVERTED_OFFERS.selector, alice, maturity));
        vm.prank(candy);
        size.buyCreditMarketOnBehalfOf(
            BuyCreditMarketOnBehalfOfParams({
                params: BuyCreditMarketParams({
                    borrower: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 500e6,
                    maturity: maturity,
                    minAPR: 0,
                    deadline: block.timestamp + 150 days,
                    exactAmountIn: false,
                    collectionId: collectionId,
                    rateProvider: bob
                }),
                onBehalfOf: candy,
                recipient: candy
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.INVERTED_OFFERS.selector, alice, maturity));
        vm.prank(candy);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 500e6,
                    maturity: maturity,
                    maxAPR: type(uint256).max,
                    deadline: block.timestamp + 150 days,
                    exactAmountIn: false,
                    collectionId: collectionId,
                    rateProvider: bob
                }),
                onBehalfOf: candy,
                recipient: candy
            })
        );
    }

    function test_Collections_subscribeToCollection_inverted_curves_many_markets() public {
        size = size2;
        _sellCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.12e18));

        size = size1;
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.03e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        CopyLimitOrderConfig memory loanCopy = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: -0.01e18
        });

        _deposit(alice, weth, 1 ether);
        _deposit(alice, usdc, 3000e6);

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, loanCopy, fullCopy);
        _subscribeToCollection(alice, collectionId);

        uint256 borrowAPRMarket1 = size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days));
        uint256 loanAPRMarket1 = size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days));
        uint256 borrowAPRMarket2 = size2.getBorrowOfferAPR(alice, RESERVED_ID, address(0), _maturity(30 days));

        assertEq(borrowAPRMarket1, 0.03e18);
        assertEq(loanAPRMarket1, 0.04e18);

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.04e18));

        borrowAPRMarket1 = size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days));
        loanAPRMarket1 = size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days));
        borrowAPRMarket2 = size2.getBorrowOfferAPR(alice, RESERVED_ID, address(0), _maturity(30 days));

        assertTrue(
            !collectionsManager.isBorrowAPRLowerThanLoanOfferAPRs(alice, borrowAPRMarket1, size, _maturity(30 days))
        );

        assertTrue(
            collectionsManager.isBorrowAPRLowerThanLoanOfferAPRs(alice, borrowAPRMarket2, size2, _maturity(30 days)),
            "On market 2, offers are OK since there is only one offer"
        );
    }

    function test_Collections_view_handles_reverting_limit_order_apr() public {
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.08e18));
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.07e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);
        _subscribeToCollection(alice, collectionId);

        uint256 pastMaturity = block.timestamp;
        assertTrue(collectionsManager.isBorrowAPRLowerThanLoanOfferAPRs(alice, 0.01e18, size, pastMaturity));
    }

    function test_Collections_subscribeToCollection_rateProvider_removes_inverted_curve_then_market_order_succeeds()
        public
    {
        _deposit(alice, usdc, 200e6);
        _deposit(candy, weth, 100e18);

        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days),
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.03e18), uint256(0.075e18), uint256(0.12e18))
            })
        );
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days),
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.15e18), uint256(0.16e18), uint256(0.17e18))
            })
        );

        CopyLimitOrderConfig memory borrowCopy =
            CopyLimitOrderConfig({minTenor: 0, maxTenor: type(uint256).max, minAPR: 0, maxAPR: 0.1e18, offsetAPR: 0});

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, fullCopy, borrowCopy);
        _subscribeToCollection(alice, collectionId);

        uint256 maturity = _maturity(30 days);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVERTED_OFFERS.selector, alice, maturity));
        vm.prank(candy);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 10e6,
                    maturity: maturity,
                    maxAPR: type(uint256).max,
                    deadline: block.timestamp,
                    exactAmountIn: false,
                    collectionId: collectionId,
                    rateProvider: bob
                }),
                onBehalfOf: candy,
                recipient: candy
            })
        );

        FixedMaturityLimitOrder memory nullOffer;
        _sellCreditLimit(bob, 0, nullOffer);

        vm.prank(candy);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 10e6,
                    maturity: maturity,
                    maxAPR: type(uint256).max,
                    deadline: block.timestamp,
                    exactAmountIn: false,
                    collectionId: collectionId,
                    rateProvider: bob
                }),
                onBehalfOf: candy,
                recipient: candy
            })
        );
    }

    function test_Collections_subscribeToCollection_rateProvider_updates_offer_then_user_market_order_reverts()
        public
    {
        _updateConfig("swapFeeAPR", 0);
        _deposit(alice, usdc, 200e6);
        _deposit(candy, weth, 100e18);

        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days),
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.03e18), uint256(0.075e18), uint256(0.12e18))
            })
        );
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days),
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.15e18), uint256(0.16e18), uint256(0.17e18))
            })
        );

        CopyLimitOrderConfig memory borrowCopy =
            CopyLimitOrderConfig({minTenor: 0, maxTenor: type(uint256).max, minAPR: 0, maxAPR: 0.1e18, offsetAPR: 0});

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _setCopyLimitOrderConfigs(alice, fullCopy, borrowCopy);
        _subscribeToCollection(alice, collectionId);

        uint256 maturity = _maturity(30 days);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVERTED_OFFERS.selector, alice, maturity));
        vm.prank(candy);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 10e6,
                    maturity: maturity,
                    maxAPR: type(uint256).max,
                    deadline: block.timestamp,
                    exactAmountIn: false,
                    collectionId: collectionId,
                    rateProvider: bob
                }),
                onBehalfOf: candy,
                recipient: candy
            })
        );

        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days),
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.01e18), uint256(0.02e18), uint256(0.03e18))
            })
        );

        vm.prank(candy);
        size.sellCreditMarketOnBehalfOf(
            SellCreditMarketOnBehalfOfParams({
                params: SellCreditMarketParams({
                    lender: alice,
                    creditPositionId: RESERVED_ID,
                    amount: 10e6,
                    maturity: maturity,
                    maxAPR: type(uint256).max,
                    deadline: block.timestamp,
                    exactAmountIn: false,
                    collectionId: collectionId,
                    rateProvider: bob
                }),
                onBehalfOf: candy,
                recipient: candy
            })
        );

        uint256 debtPositionId = 0;
        uint256 tenor = maturity - block.timestamp;
        uint256 loanAPR = size.getLoanOfferAPR(alice, collectionId, bob, maturity);
        uint256 futureValue = 10e6 + uint256(10e6 * loanAPR * tenor) / 365 days / 1e18 + 1;
        assertEq(size.getDebtPosition(debtPositionId).futureValue, futureValue);
    }

    function test_Collections_isCopyingCollectionMarketRateProvider() public {
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size1);
        _addRateProviderToCollectionMarket(james, collectionId, size1, bob);

        _subscribeToCollection(alice, collectionId);

        assertEq(collectionsManager.isCopyingCollectionMarketRateProvider(alice, collectionId + 1, size1, bob), false);
        assertEq(collectionsManager.isCopyingCollectionMarketRateProvider(alice, collectionId, size2, bob), false);
        assertEq(collectionsManager.isCopyingCollectionMarketRateProvider(alice, collectionId, size1, bob), true);
    }

    function test_Collections_subscribeToCollections_can_leave_inverted_curves_O_n_m_check() public {}

    // ============ v1.8.1 Tests: Per-Collection Config ============

    function test_Collections_setUserCollectionCopyLimitOrderConfigs_basic() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Verify default full copy after subscription
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        // Update per-collection config with restricted tenor
        CopyLimitOrderConfig memory restrictedLoanConfig = CopyLimitOrderConfig({
            minTenor: 60 days,
            maxTenor: 90 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, restrictedLoanConfig, fullCopy);

        // Should still work for borrow offer
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);

        // Should work for loan offer within bounds
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.08e18);

        // Should revert for loan offer outside bounds
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityShort());
    }

    function test_Collections_perMarket_precedence_over_perCollection() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.08e18), uint256(90 days), uint256(0.1e18)
            )
        );

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        // Set per-collection config with restricted tenor
        CopyLimitOrderConfig memory collectionConfig = CopyLimitOrderConfig({
            minTenor: 60 days,
            maxTenor: 90 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        _subscribeToCollection(alice, collectionId);
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, collectionConfig, fullCopy);

        // Verify per-collection config is active (should fail for an invalid maturity)
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        // Set per-market config with different tenor
        CopyLimitOrderConfig memory marketConfig = CopyLimitOrderConfig({
            minTenor: 30 days,
            maxTenor: 60 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        _setCopyLimitOrderConfigs(alice, marketConfig, fullCopy);

        // Per-market should take precedence - 30 days is now valid
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.08e18);

        // 90 days is outside per-market bounds (30-60 days) so should revert
        uint256 maturity90 = _maturity(90 days);
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, maturity90);
    }

    function test_Collections_perCollection_config_with_offset() public {
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.05e18), uint256(60 days), uint256(0.08e18)
            )
        );
        _sellCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.07e18), uint256(60 days), uint256(0.18e18)
            )
        );

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Set per-collection config with offset
        CopyLimitOrderConfig memory loanConfigWithOffset = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0.02e18
        });
        CopyLimitOrderConfig memory borrowConfigWithOffset = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: -0.01e18
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, loanConfigWithOffset, borrowConfigWithOffset);

        // Verify offset is applied
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.07e18); // 0.05 + 0.02
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.06e18); // 0.07 - 0.01
    }

    function test_Collections_perCollection_config_with_minMaxAPR() public {
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrderHelper.customOffer(
                uint256(30 days), uint256(0.02e18), uint256(60 days), uint256(0.15e18)
            )
        );

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Set per-collection config with min/max APR
        CopyLimitOrderConfig memory loanConfig = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0.05e18,
            maxAPR: 0.1e18,
            offsetAPR: 0
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, loanConfig, noCopy);

        // APR below minAPR should be clamped
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18); // clamped from 0.02

        // APR above maxAPR should be clamped
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, _maturity(60 days)), 0.1e18); // clamped from 0.15
    }

    function test_Collections_multiple_collections_different_configs() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(
            bob,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(30 days),
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.07e18), uint256(0.075e18), uint256(0.08e18))
            })
        );

        _sellCreditLimit(candy, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.06e18));
        _buyCreditLimit(
            candy,
            block.timestamp + 150 days,
            FixedMaturityLimitOrder({
                maturities: FixedMaturityLimitOrderHelper.maturitiesArray(
                    block.timestamp + uint256(60 days),
                    block.timestamp + uint256(90 days),
                    block.timestamp + uint256(120 days)
                ),
                aprs: FixedMaturityLimitOrderHelper.aprsArray(uint256(0.085e18), uint256(0.08625e18), uint256(0.09e18))
            })
        );

        // Create two collections with different rate providers
        uint256 collectionId1 = _createCollection(james);
        _addMarketToCollection(james, collectionId1, size);
        _addRateProviderToCollectionMarket(james, collectionId1, size, bob);

        uint256 collectionId2 = _createCollection(james);
        _addMarketToCollection(james, collectionId2, size);
        _addRateProviderToCollectionMarket(james, collectionId2, size, candy);

        _subscribeToCollection(alice, collectionId1);
        _subscribeToCollection(alice, collectionId2);

        // Set different configs for each collection
        CopyLimitOrderConfig memory config1 =
            CopyLimitOrderConfig({minTenor: 0, maxTenor: 60 days, minAPR: 0, maxAPR: type(uint256).max, offsetAPR: 0});
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId1, config1, fullCopy);

        CopyLimitOrderConfig memory config2 = CopyLimitOrderConfig({
            minTenor: 60 days,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId2, config2, fullCopy);

        // Collection 1 should work for 30 days
        assertEq(size.getLoanOfferAPR(alice, collectionId1, bob, _maturity(30 days)), 0.07e18);

        // Collection 1 should fail for an invalid maturity
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId1, bob, _invalidMaturityShort());

        // Collection 2 should work for 60 days
        // APR for 60 days: 0.085 (first point in the curve)
        assertApproxEqAbs(size.getLoanOfferAPR(alice, collectionId2, candy, _maturity(60 days)), 0.085e18, 1e15);

        // Collection 2 should fail for an invalid maturity
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId2, candy, _invalidMaturityShort());
    }

    function test_Collections_unsubscribe_clears_perCollection_config() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Set per-collection config
        CopyLimitOrderConfig memory restrictedConfig = CopyLimitOrderConfig({
            minTenor: 30 days,
            maxTenor: 60 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, noCopy, restrictedConfig);

        // Verify config is active
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);

        // Unsubscribe
        _unsubscribeFromCollection(alice, collectionId);

        assertEq(collectionsManager.isSubscribedToCollection(alice, collectionId), false);
        assertEq(collectionsManager.isCopyingCollectionMarketRateProvider(alice, collectionId, size, bob), false);

        uint256 maturity = _maturity(30 days);
        // Should revert since alice is no longer subscribed
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollectionsManagerView.InvalidCollectionMarketRateProvider.selector,
                collectionId,
                address(size),
                address(bob)
            )
        );
        size.getBorrowOfferAPR(alice, collectionId, bob, maturity);
    }

    function test_Collections_perCollection_config_market_order() public {
        _deposit(alice, usdc, 1000e6);
        _deposit(candy, weth, 100e18);

        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Set per-collection config with offset to keep spread
        CopyLimitOrderConfig memory loanConfig = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0.01e18
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, loanConfig, fullCopy);

        // Verify APRs with collection config
        uint256 maturity = block.timestamp + 30 days;
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, maturity), 0.05e18);
        assertEq(size.getLoanOfferAPR(alice, collectionId, bob, maturity), 0.09e18); // 0.08 + 0.01

        // Market order should succeed
        vm.prank(candy);
        size.sellCreditMarket(
            SellCreditMarketParams({
                lender: alice,
                creditPositionId: RESERVED_ID,
                amount: 50e6,
                maturity: maturity,
                maxAPR: type(uint256).max,
                deadline: block.timestamp + 150 days,
                exactAmountIn: false,
                collectionId: collectionId,
                rateProvider: bob
            })
        );
    }

    function test_Collections_perCollection_config_cannot_set_for_invalid_collection() public {
        uint256 invalidCollectionId = 999;

        vm.expectRevert(
            abi.encodeWithSelector(CollectionsManagerBase.InvalidCollectionId.selector, invalidCollectionId)
        );
        _setUserCollectionCopyLimitOrderConfigs(alice, invalidCollectionId, fullCopy, fullCopy);
    }

    function test_Collections_perCollection_config_only_borrow_offer() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(1, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Set per-collection config with only borrow offer
        CopyLimitOrderConfig memory borrowConfig = CopyLimitOrderConfig({
            minTenor: 30 days,
            maxTenor: 60 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, noCopy, borrowConfig);

        // Borrow offer should work within bounds
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);

        // Borrow offer should fail for an invalid maturity
        vm.expectRevert();
        size.getBorrowOfferAPR(alice, collectionId, bob, _invalidMaturityShort());

        // Loan offer should fail since it's set to noCopy
        vm.expectRevert();
        size.getLoanOfferAPR(alice, collectionId, bob, _invalidMaturityShort());
    }

    function test_Collections_perCollection_update_config_multiple_times() public {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // First config
        CopyLimitOrderConfig memory config1 =
            CopyLimitOrderConfig({minTenor: 0, maxTenor: 60 days, minAPR: 0, maxAPR: type(uint256).max, offsetAPR: 0});
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, noCopy, config1);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.05e18);

        // Update to second config
        CopyLimitOrderConfig memory config2 = CopyLimitOrderConfig({
            minTenor: 30 days,
            maxTenor: 90 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0.01e18
        });
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, noCopy, config2);
        assertEq(size.getBorrowOfferAPR(alice, collectionId, bob, _maturity(30 days)), 0.06e18); // 0.05 + 0.01

        // Update to third config (null)
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, noCopy, nullCopy);
        vm.expectRevert();
        size.getBorrowOfferAPR(alice, collectionId, bob, _invalidMaturityShort());
    }

    // ============ addMarketsToCollection revert tests ============

    function test_Collections_addMarketsToCollection_invalid_market() public {
        uint256 collectionId = _createCollection(james);

        // Create a fake market address that is not registered in the factory
        IRheo invalidMarket = IRheo(address(0x999999));

        IRheo[] memory markets = new IRheo[](1);
        markets[0] = invalidMarket;

        vm.prank(james);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MARKET.selector, address(invalidMarket)));
        collectionsManager.addMarketsToCollection(collectionId, markets);

        // Verify the market was not added to the collection
        assertEq(collectionsManager.collectionContainsMarket(collectionId, invalidMarket), false);
    }

    function test_Collections_addMarketsToCollection_paused_market() public {
        uint256 collectionId = _createCollection(james);

        // Pause the size market (owner is address(this) from BaseTest.setUp)
        size.pause();

        // Verify the market is paused
        assertTrue(size.paused());

        IRheo[] memory markets = new IRheo[](1);
        markets[0] = size;

        vm.prank(james);
        vm.expectRevert(abi.encodeWithSelector(Errors.PAUSED_MARKET.selector, address(size)));
        collectionsManager.addMarketsToCollection(collectionId, markets);

        // Verify the market was not added to the collection
        assertEq(collectionsManager.collectionContainsMarket(collectionId, size), false);
    }

    // ============ onlyRheoFactory revert tests ============

    function test_Collections_subscribeUserToCollections_onlyRheoFactory_revert() public {
        uint256 collectionId = _createCollection(james);
        uint256[] memory collectionIds = new uint256[](1);
        collectionIds[0] = collectionId;

        // Try to call subscribeUserToCollections directly on collectionsManager (not through sizeFactory)
        vm.expectRevert(abi.encodeWithSelector(CollectionsManagerBase.OnlyRheoFactory.selector, alice));
        vm.prank(alice);
        collectionsManager.subscribeUserToCollections(alice, collectionIds);
    }

    function test_Collections_unsubscribeUserFromCollections_onlyRheoFactory_revert() public {
        uint256 collectionId = _createCollection(james);

        // First subscribe through the proper channel (sizeFactory)
        _subscribeToCollection(alice, collectionId);

        uint256[] memory collectionIds = new uint256[](1);
        collectionIds[0] = collectionId;

        // Try to call unsubscribeUserFromCollections directly on collectionsManager (not through sizeFactory)
        vm.expectRevert(abi.encodeWithSelector(CollectionsManagerBase.OnlyRheoFactory.selector, alice));
        vm.prank(alice);
        collectionsManager.unsubscribeUserFromCollections(alice, collectionIds);
    }

    function test_Collections_setUserCollectionCopyLimitOrderConfigs_onlyRheoFactory_revert() public {
        uint256 collectionId = _createCollection(james);

        // First subscribe through the proper channel (sizeFactory)
        _subscribeToCollection(alice, collectionId);

        CopyLimitOrderConfig memory config = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });

        // Try to call setUserCollectionCopyLimitOrderConfigs directly on collectionsManager (not through sizeFactory)
        vm.expectRevert(abi.encodeWithSelector(CollectionsManagerBase.OnlyRheoFactory.selector, alice));
        vm.prank(alice);
        collectionsManager.setUserCollectionCopyLimitOrderConfigs(alice, collectionId, config, config);
    }

    function _invalidMaturityShort() internal view returns (uint256) {
        return block.timestamp + 45 days;
    }

    function _invalidMaturityLong() internal view returns (uint256) {
        return block.timestamp + 180 days;
    }

    // ============ Validation Tests ============

    function test_Collections_setUserCollectionCopyLimitOrderConfigs_validation_minTenor_greater_than_maxTenor()
        public
    {
        _sellCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.05e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Create invalid config where minTenor > maxTenor
        CopyLimitOrderConfig memory invalidBorrowConfig = CopyLimitOrderConfig({
            minTenor: 60 days, // minTenor > maxTenor
            maxTenor: 30 days,
            minAPR: 0,
            maxAPR: type(uint256).max,
            offsetAPR: 0
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TENOR_RANGE.selector, 60 days, 30 days));
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, noCopy, invalidBorrowConfig);
    }

    function test_Collections_setUserCollectionCopyLimitOrderConfigs_validation_minAPR_greater_than_maxAPR() public {
        _buyCreditLimit(bob, block.timestamp + 150 days, _pointOfferAtIndex(0, 0.08e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size);
        _addRateProviderToCollectionMarket(james, collectionId, size, bob);

        _subscribeToCollection(alice, collectionId);

        // Create invalid config where minAPR > maxAPR
        CopyLimitOrderConfig memory invalidLoanConfig = CopyLimitOrderConfig({
            minTenor: 0,
            maxTenor: type(uint256).max,
            minAPR: 0.2e18, // minAPR > maxAPR
            maxAPR: 0.1e18,
            offsetAPR: 0
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_APR_RANGE.selector, 0.2e18, 0.1e18));
        _setUserCollectionCopyLimitOrderConfigs(alice, collectionId, invalidLoanConfig, noCopy);
    }
}
