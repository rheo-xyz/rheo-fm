// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PropertiesConstants} from "@crytic/properties/contracts/util/PropertiesConstants.sol";
import {CREDIT_POSITION_ID_START, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {Deploy} from "@rheo-fm/script/Deploy.sol";
import {FixedMaturityLimitOrder} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";
import {Bounds} from "@rheo-fm/test/invariants/Bounds.sol";

import {PERCENT} from "@rheo-fm/src/market/libraries/Math.sol";

abstract contract Helper is Deploy, PropertiesConstants, Bounds {
    function _sortedFutureRiskMaturitiesForInvariant() internal view returns (uint256[] memory sorted) {
        uint256[] memory maturities = size.riskConfig().maturities;
        uint256 count;
        for (uint256 i = 0; i < maturities.length; i++) {
            if (maturities[i] > block.timestamp) {
                count++;
            }
        }
        sorted = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < maturities.length; i++) {
            if (maturities[i] > block.timestamp) {
                sorted[idx++] = maturities[i];
            }
        }
        for (uint256 i = 1; i < sorted.length; i++) {
            uint256 key = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > key) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = key;
        }
    }

    function _getRandomUser(address user) internal pure returns (address) {
        return uint160(user) % 3 == 0 ? USER1 : uint160(user) % 3 == 1 ? USER2 : USER3;
    }

    function _getRandomVault(address v) internal view returns (address) {
        address[] memory vaults = new address[](16);
        vaults[0] = address(0);
        vaults[1] = address(vaultSolady);
        vaults[2] = address(vaultOpenZeppelin);
        vaults[3] = address(vaultSolmate);
        vaults[4] = address(vaultMaliciousWithdrawNotAllowed);
        vaults[5] = address(vaultMaliciousReentrancy);
        vaults[6] = address(vaultMaliciousReentrancyGeneric);
        vaults[7] = address(vaultFeeOnTransfer);
        vaults[8] = address(vaultFeeOnEntryExit);
        vaults[9] = address(vaultLimits);
        vaults[10] = address(vaultNonERC4626);
        vaults[11] = address(vaultERC7540FullyAsync);
        vaults[12] = address(vaultERC7540ControlledAsyncDeposit);
        vaults[13] = address(vaultERC7540ControlledAsyncRedeem);
        vaults[14] = address(vaultInvalidUnderlying);
        vaults[15] = address(v);

        return vaults[uint256(uint160(v)) % vaults.length];
    }

    function _getCreditPositionId(uint256 creditPositionId) internal view returns (uint256) {
        (, uint256 creditPositionsCount) = size.getPositionsCount();
        if (creditPositionsCount == 0) return RESERVED_ID;

        uint256 creditPositionIdIndex = creditPositionId % creditPositionsCount;
        return creditPositionId % PERCENT < PERCENTAGE_OLD_CREDIT
            ? CREDIT_POSITION_ID_START + creditPositionIdIndex
            : RESERVED_ID;
    }

    function _getRandomOffer(uint256 seed) internal view returns (FixedMaturityLimitOrder memory) {
        uint256[] memory available = _sortedFutureRiskMaturitiesForInvariant();
        if (available.length == 0) {
            return FixedMaturityLimitOrder({maturities: new uint256[](0), aprs: new uint256[](0)});
        }

        uint256 length = available.length;
        uint256[] memory maturities = new uint256[](length);
        uint256[] memory aprs = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            maturities[i] = available[i];
            aprs[i] = 0.01e18 + ((seed ^ i) % 6) * 0.01e18;
        }
        return FixedMaturityLimitOrder({maturities: maturities, aprs: aprs});
    }
}
