// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";

/// @title BaseTestBasket
/// @notice Fixture for the basket-of-collateral tests
/// @dev The market lists WETH (18 decimals, the `setupLocal` asset) plus three assets covering the decimals the
///      product cares about: A (18), B (8) and C (6), all against the 6-decimal USDC borrow token.
abstract contract BaseTestBasket is BaseTest {
    IERC20Metadata internal assetA;
    IERC20Metadata internal assetB;
    IERC20Metadata internal assetC;

    PriceFeedMock internal priceFeedA;
    PriceFeedMock internal priceFeedB;
    PriceFeedMock internal priceFeedC;

    uint256 internal constant PRICE_A = 200e18;
    uint256 internal constant PRICE_B = 61_000e18;
    uint256 internal constant PRICE_C = 1e18;

    function setUp() public virtual override {
        uint8[] memory decimals_ = new uint8[](3);
        decimals_[0] = 18;
        decimals_[1] = 8;
        decimals_[2] = 6;

        uint256[] memory prices = new uint256[](3);
        prices[0] = PRICE_A;
        prices[1] = PRICE_B;
        prices[2] = PRICE_C;

        setupLocalBasket(address(this), feeRecipient, decimals_, prices);
        _labels();

        assetA = basketTokens[0];
        assetB = basketTokens[1];
        assetC = basketTokens[2];

        priceFeedA = basketPriceFeeds[0];
        priceFeedB = basketPriceFeeds[1];
        priceFeedC = basketPriceFeeds[2];
    }

    /// @dev The registry order is [weth, A, B, C]
    function _basketLength() internal view returns (uint256) {
        return size.getCollateralAssets().length;
    }

    /// @dev Builds an explicit seizure array sized to the registry with a single non-zero entry
    function _seizeOnly(uint256 index, uint256 amount) internal view returns (uint256[] memory amounts) {
        amounts = new uint256[](_basketLength());
        amounts[index] = amount;
    }
}
