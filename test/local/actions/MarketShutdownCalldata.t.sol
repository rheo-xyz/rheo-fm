// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {GetMarketShutdownCalldataScript} from "@rheo-fm/script/GetMarketShutdownCalldata.s.sol";

import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";

contract MarketShutdownCalldataTest is BaseTest {
    function test_MarketShutdownCalldata_collects_repaid_but_unclaimed_credit_positions() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _deposit(bob, weth, 200e18);

        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        uint256 debtPositionId = _sellCreditMarket(bob, alice, RESERVED_ID, 100e6, _maturity(150 days), false);
        uint256 creditPositionId = size.getCreditPositionIdsByDebtPositionId(debtPositionId)[0];
        uint256 futureValue = size.getDebtPosition(debtPositionId).futureValue;

        _deposit(bob, usdc, futureValue);
        _repay(bob, debtPositionId, bob);

        GetMarketShutdownCalldataScript shutdownScript = new GetMarketShutdownCalldataScript();
        MarketShutdownParams memory params = shutdownScript.collectPositions(size);

        // the debt position is repaid, so it is not force liquidated, but its credit is still outstanding
        assertEq(params.debtPositionIdsToForceLiquidate.length, 0);
        assertEq(params.creditPositionIdsToClaim.length, 1);
        assertEq(params.creditPositionIdsToClaim[0], creditPositionId);

        size.marketShutdown(params);

        assertEq(size.getCreditPosition(creditPositionId).credit, 0);
        assertEq(size.data().borrowTokenVault.balanceOf(address(size)), 0);
        assertEq(size.data().debtToken.totalSupply(), 0);
        assertEq(size.data().collateralToken.totalSupply(), 0);
    }
}
