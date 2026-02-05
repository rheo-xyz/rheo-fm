// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ITargetFunctions {
    function deposit(address token, uint256 amount) external;

    function withdraw(address token, uint256 amount) external;

    function sellCreditMarket(
        address lender,
        uint256 creditPositionId,
        uint256 amount,
        uint256 maturity,
        bool exactAmountIn
    ) external;

    function sellCreditLimit(uint256 maturity, uint256 offerSeed) external;

    function buyCreditMarket(
        address borrower,
        uint256 creditPositionId,
        uint256 maturity,
        uint256 amount,
        bool exactAmountIn
    ) external;

    function buyCreditLimit(uint256 maturity, uint256 offerSeed) external;

    function repay(uint256 debtPositionId) external;

    function claim(uint256 creditPositionId) external;

    function liquidate(uint256 debtPositionId, uint256 minimumCollateralProfit) external;

    function selfLiquidate(uint256 creditPositionId) external;

    function compensate(uint256 creditPositionWithDebtToRepayId, uint256 creditPositionToCompensateId, uint256 amount)
        external;

    function setUserConfiguration(uint256 openingLimitBorrowCR, bool allCreditPositionsForSaleDisabled) external;

    function setVault(address vault, bool forfeitOldShares) external;

    function setPrice(uint256 price) external;

    function setLiquidityIndex(uint256 liquidityIndex, uint256 supplyAmount) external;

    function updateConfig(uint256 i, uint256 value) external;
}
