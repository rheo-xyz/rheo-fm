// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {InitializeCollateralAssetParams} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";

/// @title StorageLayoutTest
/// @notice Locks the append-only storage layout that the v2.0 basket change relies on
/// @dev The basket fields were appended after `overdueLiquidationRewardPercent` so a future in-place upgrade of
///      a live market stays possible. Nothing verified that automatically, so a reorder of `Data` would
///      silently corrupt every deployed market. These tests read raw slots through `extSload` and compare them
///      against the view getters, so a field that moves fails loudly here.
contract StorageLayoutTest is BaseTest {
    /// @dev Slot indices are absolute within `State`, which itself starts at slot 0
    uint256 internal constant COLLATERAL_ASSETS_SLOT = 30;
    uint256 internal constant COLLATERAL_ASSET_INDEX_PLUS_ONE_SLOT = 31;

    function test_StorageLayout_pre_v2_fields_did_not_move() public {
        // debtTokenCap must still be readable at the slot BaseTest has always assumed
        uint256 cap = 123_456_789e6;
        _updateConfig("debtTokenCap", cap);
        assertEq(uint256(size.extSload(bytes32(DEBT_TOKEN_CAP_SLOT))), cap, "debtTokenCap moved");

        // overdueLiquidationRewardPercent sits immediately after it
        uint256 overdue = 0.037e18;
        _updateConfig("overdueLiquidationRewardPercent", overdue);
        assertEq(
            uint256(size.extSload(bytes32(OVERDUE_LIQUIDATION_REWARD_SLOT))),
            overdue,
            "overdueLiquidationRewardPercent moved"
        );
    }

    function test_StorageLayout_basket_fields_are_appended_after_them() public view {
        // a dynamic array keeps its length in its own slot; setupLocal builds a basket of one
        assertEq(
            uint256(size.extSload(bytes32(COLLATERAL_ASSETS_SLOT))),
            size.getCollateralAssets().length,
            "collateralAssets is not the slot after overdueLiquidationRewardPercent"
        );
        assertEq(uint256(size.extSload(bytes32(COLLATERAL_ASSETS_SLOT))), 1);

        // a mapping's own slot always reads as zero, and the next field must not have claimed it
        assertEq(uint256(size.extSload(bytes32(COLLATERAL_ASSET_INDEX_PLUS_ONE_SLOT))), 0);
    }

    function test_StorageLayout_collateralAssets_length_tracks_listings() public {
        assertEq(uint256(size.extSload(bytes32(COLLATERAL_ASSETS_SLOT))), 1);

        MockERC20 token = new MockERC20("Token", "TKN", 18);
        PriceFeedMock feed = new PriceFeedMock(address(this));
        feed.setPrice(1e18);
        size.addCollateralAsset(
            InitializeCollateralAssetParams({
                underlying: address(token), priceFeed: address(feed), cap: type(uint256).max
            })
        );

        assertEq(
            uint256(size.extSload(bytes32(COLLATERAL_ASSETS_SLOT))),
            2,
            "listing an asset must grow the array at the appended slot"
        );
        assertEq(size.getCollateralAssets().length, 2);
    }

    /// @dev The mapping lives at the appended slot, so its entries hash against that slot
    function test_StorageLayout_index_mapping_is_keyed_at_its_own_slot() public view {
        address underlying = address(size.getCollateralAssets()[0].underlying);
        bytes32 entry = keccak256(abi.encode(underlying, COLLATERAL_ASSET_INDEX_PLUS_ONE_SLOT));

        // the registry stores index + 1, so asset 0 reads as 1
        assertEq(uint256(size.extSload(entry)), 1, "index mapping is not at the appended slot");
    }
}
