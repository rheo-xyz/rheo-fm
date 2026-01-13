// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ProposeSafeTxUpgradeToV1_8_3Script} from "@script/ProposeSafeTxUpgradeToV1_8_3.s.sol";
import {DataView} from "@src/market/SizeViewData.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeView} from "@src/market/interfaces/ISizeView.sol";
import {Math} from "@src/market/libraries/Math.sol";
import {InitializeFeeConfigParams} from "@src/market/libraries/actions/Initialize.sol";
import {LiquidateParams} from "@src/market/libraries/actions/Liquidate.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";
import {ForkTest} from "@test/fork/ForkTest.sol";
import {SizeMock} from "@test/mocks/SizeMock.sol";
import {console} from "forge-std/console.sol";

contract ForkOverdueLiquidationRewardTest is ForkTest {
    address private constant TX_SENDER = 0xDe5C38699a7057a33524F96e62Bb1987C2568816;
    uint256 private constant TX_BLOCK = 40_450_767;
    uint256 private constant TX_TIMESTAMP = 1_767_690_881;
    uint256 private constant DEBT_POSITION_ID = 1108;

    struct Outcome {
        address borrower;
        address liquidator;
        int256 borrowerDelta;
        int256 liquidatorDelta;
        int256 protocolDelta;
        int256 futureValueUsd;
        uint256 gasUsed;
    }

    struct Vars {
        Outcome current;
        uint256 price;
        int256 currentBorrowerUsd;
        int256 currentLiquidatorUsd;
        int256 currentProtocolUsd;
    }

    struct RowVars {
        int256 borrowerUsd;
        int256 liquidatorUsd;
        int256 protocolUsd;
        uint256 breakEvenGwei;
        string row;
    }

    IERC20 private collateralTokenLocal;
    IERC20 private borrowTokenVaultLocal;
    uint256 private currentPrice;
    int256 private currentBorrowerUsd;
    int256 private currentLiquidatorUsd;
    int256 private currentProtocolUsd;

    function setUp() public override(ForkTest) {
        _resetFork();
    }

    function testFork_overdueLiquidationRewardPercentImpact() public {
        Vars memory vars;
        vars.current = _replayAndMeasure(false, 0, 0);
        _logOutcome("current", vars.current);

        console.log(
            "| Case | overdueLiquidationRewardPercent (%) | overdueCollateralProtocolPercent (%) | Borrower USD | Borrower vs FV (%) | Liquidator USD | Protocol USD | % change vs current (borrower/liquidator/protocol) | Gas used | Breakeven gas price (gwei) |"
        );
        console.log("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");

        vars.price = priceFeed.getPrice();
        currentPrice = vars.price;
        currentBorrowerUsd = _usdDelta(vars.current.borrowerDelta, vars.price);
        currentLiquidatorUsd = _usdDelta(vars.current.liquidatorDelta, vars.price);
        currentProtocolUsd = _usdDelta(vars.current.protocolDelta, vars.price);

        console.log(
            string.concat(
                "| Current (no upgrade) | n/a | n/a | ",
                _formatUsd2(currentBorrowerUsd),
                " | ",
                _formatPercent2(_borrowerVsFutureValuePercent(currentBorrowerUsd, vars.current.futureValueUsd)),
                " | ",
                _formatUsd2(currentLiquidatorUsd),
                " | ",
                _formatUsd2(currentProtocolUsd),
                " | n/a | ",
                Strings.toString(vars.current.gasUsed),
                " | ",
                _formatGwei(_breakevenGasPriceGwei(vars.current.liquidatorDelta, vars.current.gasUsed)),
                " |"
            )
        );

        uint256 step = 0.005e18; // 0.5%
        uint256 caseIndex = 0;
        for (uint256 i = 0; i <= 2; i++) {
            uint256 liquidatorPercent = step * i;
            for (uint256 j = 0; j <= 2; j++) {
                uint256 protocolPercent = step * j;
                console.log("case_index", caseIndex);
                Outcome memory upgraded = _replayAndMeasure(true, liquidatorPercent, protocolPercent);
                _logOutcome("upgraded", upgraded);

                assertEq(vars.current.borrower, upgraded.borrower, "borrower");
                assertEq(vars.current.liquidator, upgraded.liquidator, "liquidator");

                _logCaseRow(caseIndex, liquidatorPercent, protocolPercent, upgraded);

                caseIndex++;
            }
        }
    }

    function _replayAndMeasure(bool doUpgrade, uint256 overdueLiquidationRewardPercent, uint256 overdueProtocolPercent)
        internal
        returns (Outcome memory outcome)
    {
        _resetFork();
        console.log("replay.doUpgrade", doUpgrade);
        console.log("replay.overdueLiquidationRewardPercent", overdueLiquidationRewardPercent);
        console.log("replay.overdueProtocolPercent", overdueProtocolPercent);
        if (doUpgrade) {
            _upgradeToV1_8_3();
            _updateOverdueConfig(overdueLiquidationRewardPercent, overdueProtocolPercent);
        }

        uint256 borrowerPre = collateralTokenLocal.balanceOf(size.getDebtPosition(DEBT_POSITION_ID).borrower);
        uint256 liquidatorPre = collateralTokenLocal.balanceOf(TX_SENDER);
        uint256 protocolPre = collateralTokenLocal.balanceOf(ISizeView(address(size)).feeConfig().feeRecipient);
        uint256 futureValue = size.getDebtPosition(DEBT_POSITION_ID).futureValue;
        uint256 futureValueCollateral = ISizeView(address(size)).debtTokenAmountToCollateralTokenAmount(futureValue);
        int256 futureValueUsd = _usdDelta(int256(futureValueCollateral), priceFeed.getPrice());

        (
            address borrower,
            address liquidator,
            ,
            uint256 borrowerPost,
            uint256 liquidatorPost,
            uint256 protocolPost,
            uint256 gasUsed
        ) = _executeAndCapture();

        outcome.borrower = borrower;
        outcome.liquidator = liquidator;
        outcome.borrowerDelta = int256(borrowerPost) - int256(borrowerPre);
        outcome.liquidatorDelta = int256(liquidatorPost) - int256(liquidatorPre);
        outcome.protocolDelta = int256(protocolPost) - int256(protocolPre);
        outcome.futureValueUsd = futureValueUsd;
        outcome.gasUsed = gasUsed;
    }

    function _executeAndCapture()
        internal
        returns (
            address borrower,
            address liquidator,
            address feeRecipient,
            uint256 borrowerPost,
            uint256 liquidatorPost,
            uint256 protocolPost,
            uint256 gasUsed
        )
    {
        vm.warp(TX_TIMESTAMP);
        liquidator = TX_SENDER;
        borrower = size.getDebtPosition(DEBT_POSITION_ID).borrower;
        feeRecipient = ISizeView(address(size)).feeConfig().feeRecipient;

        // Use direct liquidation to keep the fork deltas deterministic.
        gasUsed = _liquidateDirect(liquidator);

        borrowerPost = collateralTokenLocal.balanceOf(borrower);
        liquidatorPost = collateralTokenLocal.balanceOf(liquidator);
        protocolPost = collateralTokenLocal.balanceOf(feeRecipient);
    }

    function _liquidateDirect(address liquidator) internal returns (uint256 gasUsed) {
        uint256 futureValue = size.getDebtPosition(DEBT_POSITION_ID).futureValue;
        uint256 balance = borrowTokenVaultLocal.balanceOf(liquidator);
        if (balance < futureValue) {
            console.log("top_up_borrowTokenVault", balance, futureValue);
            // Ensure the liquidator can repay for the fork test scenario.
            deal(address(borrowTokenVaultLocal), liquidator, futureValue);
        }
        vm.startPrank(liquidator);
        uint256 gasStart = gasleft();
        size.liquidate(
            LiquidateParams({debtPositionId: DEBT_POSITION_ID, minimumCollateralProfit: 0, deadline: type(uint256).max})
        );
        gasUsed = gasStart - gasleft();
        vm.stopPrank();
    }

    function _upgradeToV1_8_3() internal {
        ProposeSafeTxUpgradeToV1_8_3Script script = new ProposeSafeTxUpgradeToV1_8_3Script();
        (address[] memory targets, bytes[] memory datas) = script.getUpgradeToV1_8_3Data();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            (bool ok,) = targets[i].call(datas[i]);
            assertTrue(ok);
        }
    }

    function _resetFork() internal {
        vm.createSelectFork("base_archive", TX_BLOCK);
        vm.chainId(8453);
        ISize isize;
        (isize, priceFeed, owner) = importDeployments("base-production-weth-usdc");
        size = SizeMock(address(isize));
        DataView memory dataView = ISizeView(address(isize)).data();
        collateralTokenLocal = IERC20(address(dataView.collateralToken));
        borrowTokenVaultLocal = IERC20(address(dataView.borrowTokenVault));
        if (size.getDebtPosition(DEBT_POSITION_ID).futureValue == 0) {
            vm.rollFork(TX_BLOCK - 1);
            (isize, priceFeed, owner) = importDeployments("base-production-weth-usdc");
            size = SizeMock(address(isize));
            dataView = ISizeView(address(isize)).data();
            collateralTokenLocal = IERC20(address(dataView.collateralToken));
            borrowTokenVaultLocal = IERC20(address(dataView.borrowTokenVault));
        }
    }

    function _updateOverdueConfig(uint256 overdueLiquidationRewardPercent, uint256 overdueProtocolPercent) internal {
        console.log("set_overdueLiquidationRewardPercent", overdueLiquidationRewardPercent);
        vm.prank(owner);
        size.updateConfig(
            UpdateConfigParams({key: "overdueLiquidationRewardPercent", value: overdueLiquidationRewardPercent})
        );
        console.log("set_overdueCollateralProtocolPercent", overdueProtocolPercent);
        vm.prank(owner);
        size.updateConfig(UpdateConfigParams({key: "overdueCollateralProtocolPercent", value: overdueProtocolPercent}));
    }

    function _logOutcome(string memory label, Outcome memory outcome) internal pure {
        console.log(string.concat(label, ".borrower"), outcome.borrower);
        console.log(string.concat(label, ".liquidator"), outcome.liquidator);
        console.log(string.concat(label, ".borrowerDelta"), outcome.borrowerDelta);
        console.log(string.concat(label, ".liquidatorDelta"), outcome.liquidatorDelta);
        console.log(string.concat(label, ".protocolDelta"), outcome.protocolDelta);
    }

    function _formatPercent(uint256 value) internal pure returns (string memory) {
        return _formatSigned18(int256(value) * 100, 2);
    }

    function _formatSigned18(int256 value, uint256 decimals) internal pure returns (string memory) {
        bool negative = value < 0;
        uint256 absValue = uint256(negative ? -value : value);
        uint256 scale = 10 ** decimals;
        uint256 integerPart = absValue / 1e18;
        uint256 fractionalPart = (absValue / (1e18 / scale)) % scale;

        string memory integerStr = Strings.toString(integerPart);
        string memory fractionalStr = Strings.toString(fractionalPart);
        while (bytes(fractionalStr).length < decimals) {
            fractionalStr = string.concat("0", fractionalStr);
        }

        string memory sign = negative ? "-" : "";
        return string.concat(sign, integerStr, ".", fractionalStr);
    }

    function _usdDelta(int256 tokenDelta, uint256 price) internal pure returns (int256) {
        bool negative = tokenDelta < 0;
        uint256 absToken = uint256(negative ? -tokenDelta : tokenDelta);
        uint256 absUsd = Math.mulDivDown(absToken, price, 1e18);
        return negative ? -int256(absUsd) : int256(absUsd);
    }

    function _formatUsd2(int256 usdValue) internal pure returns (string memory) {
        bool negative = usdValue < 0;
        uint256 absValue = uint256(negative ? -usdValue : usdValue);
        string memory absString = _formatSigned18(int256(absValue), 2);
        if (negative) {
            return string.concat("-$", absString);
        }
        return string.concat("$", absString);
    }

    function _formatPercentChange(int256 newUsd, int256 currentUsd) internal pure returns (string memory) {
        if (currentUsd == 0) {
            return "n/a";
        }
        int256 delta = newUsd - currentUsd;
        bool negative = (delta < 0) != (currentUsd < 0);
        uint256 absDelta = uint256(delta < 0 ? -delta : delta);
        uint256 absCurrent = uint256(currentUsd < 0 ? -currentUsd : currentUsd);
        uint256 absPercent = Math.mulDivDown(absDelta, 100e18, absCurrent);
        int256 percent = negative ? -int256(absPercent) : int256(absPercent);
        return string.concat(_formatSigned18(percent, 2), "%");
    }

    function _borrowerVsFutureValuePercent(int256 borrowerUsd, int256 futureValueUsd) internal pure returns (int256) {
        if (futureValueUsd == 0) {
            return 0;
        }
        // Compare borrower loss against FV: (loss - FV) / FV.
        uint256 lossUsd = borrowerUsd < 0 ? uint256(-borrowerUsd) : uint256(borrowerUsd);
        uint256 fvUsd = futureValueUsd < 0 ? uint256(-futureValueUsd) : uint256(futureValueUsd);
        if (fvUsd == 0) {
            return 0;
        }
        int256 delta = int256(lossUsd) - int256(fvUsd);
        bool negative = delta < 0;
        uint256 absDelta = uint256(negative ? -delta : delta);
        uint256 absPercent = Math.mulDivDown(absDelta, 100e18, fvUsd);
        return negative ? -int256(absPercent) : int256(absPercent);
    }

    function _formatPercent2(int256 percent) internal pure returns (string memory) {
        return string.concat(_formatSigned18(percent, 2), "%");
    }

    function _logCaseRow(uint256 caseIndex, uint256 liquidatorPercent, uint256 protocolPercent, Outcome memory upgraded)
        internal
        view
    {
        RowVars memory vars;
        vars.borrowerUsd = _usdDelta(upgraded.borrowerDelta, currentPrice);
        vars.liquidatorUsd = _usdDelta(upgraded.liquidatorDelta, currentPrice);
        vars.protocolUsd = _usdDelta(upgraded.protocolDelta, currentPrice);
        vars.breakEvenGwei = _breakevenGasPriceGwei(upgraded.liquidatorDelta, upgraded.gasUsed);

        vars.row = string.concat("| ", Strings.toString(caseIndex), " | ");
        vars.row = string.concat(vars.row, _formatPercent(liquidatorPercent), " | ");
        vars.row = string.concat(vars.row, _formatPercent(protocolPercent), " | ");
        vars.row = string.concat(vars.row, _formatUsd2(vars.borrowerUsd), " | ");
        vars.row = string.concat(
            vars.row, _formatPercent2(_borrowerVsFutureValuePercent(vars.borrowerUsd, upgraded.futureValueUsd)), " | "
        );
        vars.row = string.concat(vars.row, _formatUsd2(vars.liquidatorUsd), " | ");
        vars.row = string.concat(vars.row, _formatUsd2(vars.protocolUsd), " | ");
        vars.row = string.concat(
            vars.row,
            _formatPercentChange(vars.borrowerUsd, currentBorrowerUsd),
            " / ",
            _formatPercentChange(vars.liquidatorUsd, currentLiquidatorUsd),
            " / "
        );
        vars.row = string.concat(
            vars.row,
            _formatPercentChange(vars.protocolUsd, currentProtocolUsd),
            " | ",
            Strings.toString(upgraded.gasUsed),
            " | "
        );
        vars.row = string.concat(vars.row, _formatGwei(vars.breakEvenGwei), " |");

        console.log(vars.row);
    }

    function _breakevenGasPriceGwei(int256 liquidatorDelta, uint256 gasUsed) internal pure returns (uint256) {
        if (gasUsed == 0) {
            return 0;
        }
        if (liquidatorDelta <= 0) {
            return 0;
        }
        // liquidatorDelta is in collateral token wei, assume collateral is WETH for gas cost.
        uint256 priceWeiPerGas = uint256(liquidatorDelta) / gasUsed;
        return priceWeiPerGas / 1e9;
    }

    function _formatGwei(uint256 value) internal pure returns (string memory) {
        return string.concat(Strings.toString(value), " gwei");
    }
}
