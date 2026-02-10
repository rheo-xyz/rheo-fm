// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BaseScript} from "@rheo-fm/script/BaseScript.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";
import {
    CREDIT_POSITION_ID_START,
    CreditPosition,
    DEBT_POSITION_ID_START,
    DebtPosition
} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {MarketShutdownParams} from "@rheo-fm/src/market/libraries/actions/MarketShutdown.sol";

contract GetMarketShutdownCalldataScript is BaseScript, Networks {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(IRheo market => EnumerableSet.AddressSet) private borrowersByMarket;
    mapping(IRheo market => EnumerableSet.AddressSet) private lendersByMarket;
    mapping(IRheo market => EnumerableSet.UintSet) private debtPositionIdsByMarket;
    mapping(IRheo market => EnumerableSet.UintSet) private creditPositionIdsByMarket;
    mapping(IRheo market => uint256) private sumFutureValueByMarket;

    address[2] private extraUsersWithCollateral =
        [0x83eCCb05386B2d10D05e1BaEa8aC89b5B7EA8290, 0x12328eA44AB6D7B18aa9Cc030714763734b625dB];

    function run() public pure {}

    function getMarketShutdownCalldata(IRheo market) public returns (bytes memory calldata_) {
        MarketShutdownParams memory shutdownParams = collectPositions(market);
        calldata_ = abi.encodeCall(IRheoAdmin.marketShutdown, (shutdownParams));
    }

    function getMarketShutdownCalldataWithMaxIds(IRheo market, uint256 maxDebtIds, uint256 maxCreditIds)
        public
        returns (bytes memory calldata_)
    {
        MarketShutdownParams memory shutdownParams = _collectPositions(market, maxDebtIds, maxCreditIds);
        calldata_ = abi.encodeCall(IRheoAdmin.marketShutdown, (shutdownParams));
    }

    function collectPositions(IRheo market) public returns (MarketShutdownParams memory params) {
        params = _collectPositions(market, type(uint256).max, type(uint256).max);
    }

    function getBorrowers(IRheo market) external view returns (address[] memory) {
        return borrowersByMarket[market].values();
    }

    function getLenders(IRheo market) external view returns (address[] memory) {
        return lendersByMarket[market].values();
    }

    function getDebtPositionIds(IRheo market) external view returns (uint256[] memory) {
        return debtPositionIdsByMarket[market].values();
    }

    function getCreditPositionIds(IRheo market) external view returns (uint256[] memory) {
        return creditPositionIdsByMarket[market].values();
    }

    function getSumFutureValue(IRheo market) external view returns (uint256) {
        return sumFutureValueByMarket[market];
    }

    function collectPositions(IRheo market) public returns (MarketShutdownParams memory params) {
        return _collectPositions(market, type(uint256).max, type(uint256).max);
    }

    function _collectPositions(IRheo market, uint256 maxDebtIds, uint256 maxCreditIds)
        private
        returns (MarketShutdownParams memory params)
    {
        IRheoView marketView = IRheoView(address(market));
        DataView memory dataView = marketView.data();

        EnumerableSet.AddressSet storage borrowers = borrowersByMarket[market];
        EnumerableSet.AddressSet storage lenders = lendersByMarket[market];
        EnumerableSet.UintSet storage debtPositionIds = debtPositionIdsByMarket[market];
        EnumerableSet.UintSet storage creditPositionIds = creditPositionIdsByMarket[market];

        borrowers.clear();
        lenders.clear();
        debtPositionIds.clear();
        creditPositionIds.clear();
        sumFutureValueByMarket[market] = 0;

        uint256 debtStop = dataView.nextDebtPositionId;
        if (maxDebtIds < debtStop) {
            debtStop = maxDebtIds;
        }

        for (uint256 debtPositionId = DEBT_POSITION_ID_START; debtPositionId < debtStop; debtPositionId++) {
            DebtPosition memory debtPosition = marketView.getDebtPosition(debtPositionId);
            if (debtPosition.futureValue > 0) {
                borrowers.add(debtPosition.borrower);
                debtPositionIds.add(debtPositionId);
                sumFutureValueByMarket[market] += debtPosition.futureValue;
            } else if (dataView.collateralToken.balanceOf(debtPosition.borrower) > 0) {
                borrowers.add(debtPosition.borrower);
            }
        }

        uint256 creditStop = dataView.nextCreditPositionId;
        if (maxCreditIds != type(uint256).max) {
            uint256 creditLimitId = CREDIT_POSITION_ID_START + maxCreditIds;
            if (creditLimitId < creditStop) {
                creditStop = creditLimitId;
            }
        }

        for (uint256 creditPositionId = CREDIT_POSITION_ID_START; creditPositionId < creditStop; creditPositionId++) {
            CreditPosition memory creditPosition = marketView.getCreditPosition(creditPositionId);
            if (creditPosition.credit == 0 || !debtPositionIds.contains(creditPosition.debtPositionId)) {
                continue;
            }

            creditPositionIds.add(creditPositionId);
            lenders.add(creditPosition.lender);
        }

        borrowers.add(marketView.feeConfig().feeRecipient);
        borrowers.add(contracts[block.chainid][Contract.RHEO_GOVERNANCE]);
        for (uint256 i = 0; i < extraUsersWithCollateral.length; i++) {
            borrowers.add(extraUsersWithCollateral[i]);
        }

        params = MarketShutdownParams({
            debtPositionIdsToForceLiquidate: debtPositionIds.values(),
            creditPositionIdsToClaim: creditPositionIds.values(),
            usersToForceWithdraw: borrowers.values(),
            shouldCheckSupply: true
        });
    }
}
