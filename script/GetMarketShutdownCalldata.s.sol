// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {DataView} from "@src/market/SizeViewData.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";
import {ISizeView} from "@src/market/interfaces/ISizeView.sol";
import {
    CREDIT_POSITION_ID_START,
    CreditPosition,
    DEBT_POSITION_ID_START,
    DebtPosition
} from "@src/market/libraries/LoanLibrary.sol";
import {MarketShutdownParams} from "@src/market/libraries/actions/MarketShutdown.sol";

contract GetMarketShutdownCalldataScript is BaseScript, Networks {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(ISize market => EnumerableSet.AddressSet) private borrowersByMarket;
    mapping(ISize market => EnumerableSet.AddressSet) private lendersByMarket;
    mapping(ISize market => EnumerableSet.UintSet) private debtPositionIdsByMarket;
    mapping(ISize market => EnumerableSet.UintSet) private creditPositionIdsByMarket;
    mapping(ISize market => uint256) private sumFutureValueByMarket;

    function run() public pure {}

    function getMarketShutdownCalldata(ISize market) public returns (bytes memory calldata_) {
        MarketShutdownParams memory shutdownParams = collectPositions(market);
        calldata_ = abi.encodeCall(ISizeAdmin.marketShutdown, (shutdownParams));
    }

    function getBorrowers(ISize market) external view returns (address[] memory) {
        return borrowersByMarket[market].values();
    }

    function getLenders(ISize market) external view returns (address[] memory) {
        return lendersByMarket[market].values();
    }

    function getDebtPositionIds(ISize market) external view returns (uint256[] memory) {
        return debtPositionIdsByMarket[market].values();
    }

    function getCreditPositionIds(ISize market) external view returns (uint256[] memory) {
        return creditPositionIdsByMarket[market].values();
    }

    function getSumFutureValue(ISize market) external view returns (uint256) {
        return sumFutureValueByMarket[market];
    }

    function collectPositions(ISize market) public returns (MarketShutdownParams memory params) {
        ISizeView marketView = ISizeView(address(market));
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

        for (
            uint256 debtPositionId = DEBT_POSITION_ID_START;
            debtPositionId < dataView.nextDebtPositionId;
            debtPositionId++
        ) {
            DebtPosition memory debtPosition = marketView.getDebtPosition(debtPositionId);
            if (debtPosition.futureValue > 0) {
                borrowers.add(debtPosition.borrower);
                debtPositionIds.add(debtPositionId);
                sumFutureValueByMarket[market] += debtPosition.futureValue;
            } else if (dataView.collateralToken.balanceOf(debtPosition.borrower) > 0) {
                borrowers.add(debtPosition.borrower);
            }
        }

        for (
            uint256 creditPositionId = CREDIT_POSITION_ID_START;
            creditPositionId < dataView.nextCreditPositionId;
            creditPositionId++
        ) {
            CreditPosition memory creditPosition = marketView.getCreditPosition(creditPositionId);
            if (creditPosition.credit == 0 || !debtPositionIds.contains(creditPosition.debtPositionId)) {
                continue;
            }

            creditPositionIds.add(creditPositionId);
            lenders.add(creditPosition.lender);
        }

        borrowers.add(marketView.feeConfig().feeRecipient);
        borrowers.add(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
        address[2] memory extraUsers =
            [address(0x83eCCb05386B2d10D05e1BaEa8aC89b5B7EA8290), address(0x12328eA44AB6D7B18aa9Cc030714763734b625dB)];
        for (uint256 i = 0; i < extraUsers.length; i++) {
            borrowers.add(extraUsers[i]);
        }

        params = MarketShutdownParams({
            debtPositionIdsToForceLiquidate: debtPositionIds.values(),
            creditPositionIdsToClaim: creditPositionIds.values(),
            usersToForceWithdraw: borrowers.values(),
            shouldCheckSupply: true
        });
    }
}
