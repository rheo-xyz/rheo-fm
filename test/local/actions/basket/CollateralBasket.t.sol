// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {MAX_COLLATERAL_ASSETS} from "@rheo-fm/src/market/RheoStorage.sol";
import {CollateralAssetView} from "@rheo-fm/src/market/RheoViewData.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {Math, PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {InitializeCollateralAssetParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";

import {BaseTestBasket} from "@rheo-fm/test/local/actions/basket/BaseTestBasket.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";

contract CollateralBasketTest is BaseTestBasket {
    // --- registry and admin ---

    function test_CollateralBasket_registry_lists_every_asset_in_order() public view {
        CollateralAssetView[] memory assets = size.getCollateralAssets();

        assertEq(assets.length, 4);
        assertEq(address(assets[0].underlying), address(weth));
        assertEq(address(assets[1].underlying), address(assetA));
        assertEq(address(assets[2].underlying), address(assetB));
        assertEq(address(assets[3].underlying), address(assetC));

        assertEq(address(assets[1].priceFeed), address(priceFeedA));
        assertEq(assets[1].cap, type(uint256).max);
        assertTrue(!assets[1].depositPaused);
    }

    function test_CollateralBasket_legacy_views_mirror_the_first_asset() public view {
        assertEq(address(size.data().underlyingCollateralToken), address(weth));
        assertEq(address(size.data().collateralToken), address(size.getCollateralAssets()[0].token));
        assertEq(size.oracle().priceFeed, address(priceFeed));
    }

    function test_CollateralBasket_addCollateralAsset_rejects_a_duplicate() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.COLLATERAL_ASSET_ALREADY_LISTED.selector, address(assetA)));
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(assetA), priceFeed: address(priceFeedA), cap: type(uint256).max
            })
        );
    }

    function test_CollateralBasket_addCollateralAsset_rejects_the_borrow_token() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TOKEN.selector, address(usdc)));
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(usdc), priceFeed: address(priceFeedA), cap: type(uint256).max
            })
        );
    }

    function test_CollateralBasket_addCollateralAsset_rejects_a_feed_without_18_decimals() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);
        PriceFeedWrongDecimals feed = new PriceFeedWrongDecimals();

        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_PRICE_FEED_DECIMALS.selector, 8));
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(token), priceFeed: address(feed), cap: type(uint256).max
            })
        );
    }

    function test_CollateralBasket_addCollateralAsset_rejects_a_dead_feed() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);
        PriceFeedMock feed = new PriceFeedMock(address(this)); // price defaults to 0

        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_AMOUNT.selector));
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(token), priceFeed: address(feed), cap: type(uint256).max
            })
        );
    }

    function test_CollateralBasket_addCollateralAsset_enforces_the_registry_limit() public {
        // the fixture already lists 4 assets
        for (uint256 i = size.getCollateralAssets().length; i < MAX_COLLATERAL_ASSETS; i++) {
            _listAsset(18, 1e18);
        }
        assertEq(size.getCollateralAssets().length, MAX_COLLATERAL_ASSETS);

        MockERC20 token = new MockERC20("Token", "TKN", 18);
        PriceFeedMock feed = new PriceFeedMock(address(this));
        feed.setPrice(1e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.COLLATERAL_ASSETS_LIMIT_EXCEEDED.selector, MAX_COLLATERAL_ASSETS));
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(token), priceFeed: address(feed), cap: type(uint256).max
            })
        );
    }

    function test_CollateralBasket_addCollateralAsset_is_admin_only() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);
        PriceFeedMock feed = new PriceFeedMock(address(this));
        feed.setPrice(1e18);

        vm.prank(alice);
        vm.expectRevert();
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(token), priceFeed: address(feed), cap: type(uint256).max
            })
        );
    }

    function test_CollateralBasket_setters_revert_for_an_unlisted_asset() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);

        vm.expectRevert(abi.encodeWithSelector(Errors.COLLATERAL_ASSET_NOT_LISTED.selector, address(token)));
        size.setCollateralAssetCap(address(token), 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.COLLATERAL_ASSET_NOT_LISTED.selector, address(token)));
        size.setCollateralAssetDepositPaused(address(token), true);
    }

    // --- deposit and withdraw ---

    function test_CollateralBasket_deposit_and_withdraw_each_asset_one_to_one() public {
        _deposit(alice, assetA, 3e18);
        _deposit(alice, assetB, 2e8);
        _deposit(alice, assetC, 5e6);

        (address[] memory underlyings, uint256[] memory balances) = size.getUserCollateralBalances(alice);
        assertEq(underlyings.length, 4);
        assertEq(balances[0], 0); // weth
        assertEq(balances[1], 3e18);
        assertEq(balances[2], 2e8);
        assertEq(balances[3], 5e6);

        _withdraw(alice, assetB, 2e8);
        (, balances) = size.getUserCollateralBalances(alice);
        assertEq(balances[2], 0);
        assertEq(assetB.balanceOf(alice), 2e8);
    }

    function test_CollateralBasket_deposit_rejects_an_unlisted_token() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);
        _mint(address(token), alice, 1e18);
        _approve(alice, address(token), address(size), 1e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TOKEN.selector, address(token)));
        size.deposit(DepositParams({token: address(token), amount: 1e18, to: alice}));
    }

    function test_CollateralBasket_deposit_respects_the_cap_and_withdraw_still_works() public {
        size.setCollateralAssetCap(address(assetA), 10e18);

        _deposit(alice, assetA, 10e18); // exactly at the cap

        _mint(address(assetA), alice, 1);
        _approve(alice, address(assetA), address(size), 1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.COLLATERAL_ASSET_CAP_EXCEEDED.selector, address(assetA), 10e18, 10e18 + 1)
        );
        size.deposit(DepositParams({token: address(assetA), amount: 1, to: alice}));

        // lowering the cap below the current supply blocks deposits but never exits
        size.setCollateralAssetCap(address(assetA), 1);
        _withdraw(alice, assetA, 10e18);
        assertEq(assetA.balanceOf(alice), 10e18 + 1);
    }

    function test_CollateralBasket_depositPaused_blocks_deposits_but_not_withdrawals() public {
        _deposit(alice, assetA, 5e18);

        size.setCollateralAssetDepositPaused(address(assetA), true);

        _mint(address(assetA), alice, 1e18);
        _approve(alice, address(assetA), address(size), 1e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.COLLATERAL_ASSET_DEPOSIT_PAUSED.selector, address(assetA)));
        size.deposit(DepositParams({token: address(assetA), amount: 1e18, to: alice}));

        _withdraw(alice, assetA, 5e18);
        assertEq(assetA.balanceOf(alice), 5e18 + 1e18);
    }

    function test_CollateralBasket_withdraw_rejects_an_unlisted_token() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_TOKEN.selector, address(token)));
        size.withdraw(WithdrawParams({token: address(token), amount: 1e18, to: alice}));
    }

    /// @dev The cap must bind on the amount actually minted. On the msg.value path the deposited amount is the
    ///      contract balance, which can exceed the `params.amount` the validation sees when the market already
    ///      holds ETH (for example force-sent).
    function test_CollateralBasket_deposit_cap_binds_on_the_msg_value_path() public {
        size.setCollateralAssetCap(address(weth), 10e18);

        // the market already holds ETH that is not accounted for by params.amount
        vm.deal(address(size), 5e18);
        vm.deal(alice, 10e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.COLLATERAL_ASSET_CAP_EXCEEDED.selector, address(weth), 10e18, 15e18)
        );
        size.deposit{value: 10e18}(DepositParams({token: address(weth), amount: 10e18, to: alice}));
    }

    function test_CollateralBasket_deposit_msg_value_path_mints_within_the_cap() public {
        size.setCollateralAssetCap(address(weth), 10e18);
        vm.deal(alice, 10e18);

        vm.prank(alice);
        size.deposit{value: 10e18}(DepositParams({token: address(weth), amount: 10e18, to: alice}));

        (, uint256[] memory balances) = size.getUserCollateralBalances(alice);
        assertEq(balances[0], 10e18);
    }

    // --- collateral ratio and valuation ---

    function test_CollateralBasket_collateralValue_sums_mixed_decimals() public {
        _deposit(alice, assetA, 3e18); // 3 * 200 = 600 USDC
        _deposit(alice, assetB, 2e8); // 2 * 61_000 = 122_000 USDC
        _deposit(alice, assetC, 5e6); // 5 * 1 = 5 USDC

        assertEq(size.collateralValue(alice), 600e6 + 122_000e6 + 5e6);
    }

    function test_CollateralBasket_getCollateralAssetValue_matches_hand_computation() public view {
        assertEq(size.getCollateralAssetValue(address(assetA), 1e18), 200e6);
        assertEq(size.getCollateralAssetValue(address(assetB), 1e8), 61_000e6);
        assertEq(size.getCollateralAssetValue(address(assetC), 1e6), 1e6);
    }

    function test_CollateralBasket_getCollateralAssetValue_reverts_for_an_unlisted_asset() public {
        MockERC20 token = new MockERC20("Token", "TKN", 18);
        vm.expectRevert(abi.encodeWithSelector(Errors.COLLATERAL_ASSET_NOT_LISTED.selector, address(token)));
        size.getCollateralAssetValue(address(token), 1e18);
    }

    function test_CollateralBasket_collateralRatio_spans_the_whole_basket() public {
        _deposit(alice, usdc, 1_000e6);
        _deposit(bob, assetA, 1e18); // 200 USDC
        _deposit(bob, assetC, 100e6); // 100 USDC

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.1e18));
        _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);

        uint256 debt = size.getUserView(bob).debtBalance;
        assertEq(size.collateralRatio(bob), Math.mulDivDown(300e6, PERCENT, debt));
    }

    // --- oracle failure containment (the zero-balance skip) ---

    function test_CollateralBasket_a_dead_feed_only_affects_holders_of_that_asset() public {
        BreakablePriceFeed feed = new BreakablePriceFeed();
        size.setCollateralAssetPriceFeed(address(assetB), address(feed));

        _deposit(alice, assetA, 1e18);
        _deposit(bob, assetC, 100e6);
        _deposit(candy, assetB, 1e8);

        // asset B's feed goes dark after listing
        feed.breakFeed();

        // the zero-balance skip keeps the blast radius to actual holders of B
        assertEq(size.collateralValue(alice), 200e6);
        assertEq(size.collateralValue(bob), 100e6);

        vm.expectRevert();
        size.collateralValue(candy);
    }

    function _listAsset(uint8 decimals_, uint256 price) private returns (IERC20Metadata token) {
        MockERC20 erc20 = new MockERC20("Token", "TKN", decimals_);
        PriceFeedMock feed = new PriceFeedMock(address(this));
        feed.setPrice(price);
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(erc20), priceFeed: address(feed), cap: type(uint256).max
            })
        );
        token = IERC20Metadata(address(erc20));
    }
}

/// @dev A feed reporting the wrong number of decimals, rejected at listing
contract PriceFeedWrongDecimals {
    function getPrice() external pure returns (uint256) {
        return 1e18;
    }

    function decimals() external pure returns (uint256) {
        return 8;
    }
}

/// @dev A feed that is healthy at listing and can be made to go dark afterwards, used to pin the
///      oracle-failure blast radius
contract BreakablePriceFeed {
    bool public broken;

    function breakFeed() external {
        broken = true;
    }

    function getPrice() external view returns (uint256) {
        if (broken) {
            revert("feed is down");
        }
        return 61_000e18;
    }

    function decimals() external pure returns (uint256) {
        return 18;
    }
}
