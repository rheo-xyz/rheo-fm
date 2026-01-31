// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {GetMarketShutdownCalldataScript} from "@script/GetMarketShutdownCalldata.s.sol";
import {Contract, Networks} from "@script/Networks.sol";
import {ProposeSafeTxUpgradeToV1_8_4Script} from "@script/ProposeSafeTxUpgradeToV1_8_4.s.sol";
import {ForkTest} from "@test/fork/ForkTest.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {DataView} from "@src/market/SizeViewData.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";
import {ISizeView} from "@src/market/interfaces/ISizeView.sol";

import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";
import {WithdrawParams} from "@src/market/libraries/actions/Withdraw.sol";
import {NonTransferrableRebasingTokenVault} from "@src/market/token/NonTransferrableRebasingTokenVault.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract ForkMarketShutdownTest is ForkTest, Networks {
    ISize private cbEthUsdc;
    ISize private wethUsdc;
    IERC20Metadata private borrowTokenLocal;
    NonTransferrableRebasingTokenVault private borrowTokenVaultLocal;

    function setUp() public override(ForkTest) {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string memory rpcUrl = bytes(alchemyKey).length == 0
            ? "https://cloudflare-eth.com"
            : string.concat("https://eth-mainnet.g.alchemy.com/v2/", alchemyKey);
        vm.createSelectFork(rpcUrl);
        vm.chainId(1);

        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        owner = Networks.contracts[block.chainid][Contract.SIZE_GOVERNANCE];

        cbEthUsdc = sizeFactory.getMarket(2);
        wethUsdc = sizeFactory.getMarket(0);

        DataView memory dataView = ISizeView(address(cbEthUsdc)).data();
        borrowTokenLocal = dataView.underlyingBorrowToken;
        borrowTokenVaultLocal = dataView.borrowTokenVault;
    }

    function testFork_MarketShutdown_shutdown_liquidates_borrowers_forces_withdraw_lenders_but_can_still_withdraw()
        public
    {
        GetMarketShutdownCalldataScript shutdownScript = new GetMarketShutdownCalldataScript();
        bytes memory shutdownCalldata = shutdownScript.getMarketShutdownCalldataWithMaxIds(cbEthUsdc, 5, 5);

        uint256[] memory debtPositionIdsArray = shutdownScript.getDebtPositionIds(cbEthUsdc);
        uint256[] memory creditPositionIdsArray = shutdownScript.getCreditPositionIds(cbEthUsdc);
        assertGt(debtPositionIdsArray.length, 0, "no open debt positions");
        assertGt(creditPositionIdsArray.length, 0, "no claimable credit positions");
        address[] memory lendersArray = shutdownScript.getLenders(cbEthUsdc);
        assertGt(lendersArray.length, 0, "no lenders found");

        uint256 depositAmount = shutdownScript.getSumFutureValue(cbEthUsdc);
        deal(address(borrowTokenLocal), owner, depositAmount);
        vm.prank(owner);
        borrowTokenLocal.approve(address(cbEthUsdc), depositAmount);
        vm.prank(owner);
        cbEthUsdc.deposit(DepositParams({token: address(borrowTokenLocal), amount: depositAmount, to: owner}));

        ProposeSafeTxUpgradeToV1_8_4Script upgradeScript = new ProposeSafeTxUpgradeToV1_8_4Script();
        (address[] memory targets, bytes[] memory datas) = upgradeScript.getUpgradeToV1_8_4Data();
        _upgradeToV1_8_4(targets, datas);

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = shutdownCalldata;
        multicallData[1] = abi.encodeCall(ISizeAdmin.pause, ());

        vm.prank(owner);
        cbEthUsdc.multicall(multicallData);

        assertTrue(PausableUpgradeable(address(cbEthUsdc)).paused());
        DataView memory cbEthData = ISizeView(address(cbEthUsdc)).data();
        assertEq(cbEthData.debtToken.totalSupply(), 0);
        assertEq(cbEthData.collateralToken.totalSupply(), 0);

        assertFalse(PausableUpgradeable(address(wethUsdc)).paused());
        DataView memory wethUsdcData = ISizeView(address(wethUsdc)).data();
        assertEq(address(wethUsdcData.borrowTokenVault), address(borrowTokenVaultLocal));

        for (uint256 i = 0; i < lendersArray.length; i++) {
            address lender = lendersArray[i];
            uint256 lenderVaultBalance = borrowTokenVaultLocal.balanceOf(lender);
            assertGt(lenderVaultBalance, 0);

            uint256 lenderBorrowBalanceBefore = borrowTokenLocal.balanceOf(lender);
            vm.prank(lender);
            wethUsdc.withdraw(
                WithdrawParams({token: address(borrowTokenLocal), amount: lenderVaultBalance, to: lender})
            );
            uint256 lenderBorrowBalanceAfter = borrowTokenLocal.balanceOf(lender);

            assertEqApprox(lenderBorrowBalanceAfter, lenderBorrowBalanceBefore + lenderVaultBalance, 1);
        }
    }

    function _upgradeToV1_8_4(address[] memory targets, bytes[] memory datas) internal {
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
