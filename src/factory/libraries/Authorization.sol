// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice User-defined value type for the actions bitmap.
type ActionsBitmap is uint256;

/// @notice The actions that can be authorized.
/// @dev Keep the order stable to preserve bitmap semantics.
enum Action {
    DEPOSIT,
    WITHDRAW,
    BUY_CREDIT_LIMIT,
    SELL_CREDIT_LIMIT,
    BUY_CREDIT_MARKET,
    SELL_CREDIT_MARKET,
    SELF_LIQUIDATE,
    COMPENSATE,
    SET_USER_CONFIGURATION,
    SET_COPY_LIMIT_ORDER_CONFIGS,
    SET_VAULT,
    MANAGE_COLLECTION_SUBSCRIPTIONS,
    NUMBER_OF_ACTIONS
}

library Authorization {
    function toUint256(ActionsBitmap actionsBitmap) internal pure returns (uint256) {
        return uint256(ActionsBitmap.unwrap(actionsBitmap));
    }

    function toActionsBitmap(uint256 value) internal pure returns (ActionsBitmap) {
        return ActionsBitmap.wrap(value);
    }

    function nullActionsBitmap() internal pure returns (ActionsBitmap) {
        return toActionsBitmap(0);
    }

    function isValid(ActionsBitmap actionsBitmap) internal pure returns (bool) {
        uint256 maxValidBitmap = (1 << uint256(Action.NUMBER_OF_ACTIONS)) - 1;
        return toUint256(actionsBitmap) <= maxValidBitmap;
    }

    function isActionSet(ActionsBitmap actionsBitmap, Action action) internal pure returns (bool) {
        return (toUint256(actionsBitmap) & (1 << uint256(action))) != 0;
    }

    function getActionsBitmap(Action action) internal pure returns (ActionsBitmap) {
        return toActionsBitmap(1 << uint256(action));
    }

    function getActionsBitmap(Action[] memory actions) internal pure returns (ActionsBitmap) {
        uint256 actionsBitmapUint256 = 0;
        for (uint256 i = 0; i < actions.length; i++) {
            actionsBitmapUint256 |= toUint256(getActionsBitmap(actions[i]));
        }
        return toActionsBitmap(actionsBitmapUint256);
    }
}
