// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {GetMarketShutdownCalldataScript} from "@rheo-fm/script/GetMarketShutdownCalldata.s.sol";
import {Contract, Networks} from "@rheo-fm/script/Networks.sol";
import {ForkTest} from "@rheo-fm/test/fork/ForkTest.sol";

import {RheoFactory} from "@rheo-fm/src/factory/RheoFactory.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {IRheoView} from "@rheo-fm/src/market/interfaces/IRheoView.sol";

import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract ForkMarketShutdownTest is ForkTest, Networks {
    IRheo private cbEthUsdc;
    IRheo private wethUsdc;
    IERC20Metadata private borrowTokenLocal;
    NonTransferrableRebasingTokenVault private borrowTokenVaultLocal;

    function setUp() public override(ForkTest) {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string memory rpcUrl = bytes(alchemyKey).length == 0
            ? "https://cloudflare-eth.com"
            : string.concat("https://eth-mainnet.g.alchemy.com/v2/", alchemyKey);
        vm.createSelectFork(rpcUrl, 24_336_785);
        vm.chainId(1);

        sizeFactory = RheoFactory(contracts[block.chainid][Contract.RHEO_FACTORY]);
        owner = Networks.contracts[block.chainid][Contract.RHEO_GOVERNANCE];

        cbEthUsdc = sizeFactory.getMarket(12);
        wethUsdc = sizeFactory.getMarket(0);

        DataView memory dataView = IRheoView(address(cbEthUsdc)).data();
        borrowTokenLocal = dataView.underlyingBorrowToken;
        borrowTokenVaultLocal = dataView.borrowTokenVault;
    }

    function testFork_MarketShutdown_shutdown_liquidates_borrowers_forces_withdraw_lenders_but_can_still_withdraw()
        public
    {
        GetMarketShutdownCalldataScript shutdownScript = new GetMarketShutdownCalldataScript();
        bytes memory shutdownCalldata = shutdownScript.getMarketShutdownCalldataWithMaxIds(cbEthUsdc, 12, 12);

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

        Rheo newRheoImplementation = new Rheo();
        address[] memory targets = new address[](1);
        bytes[] memory datas = new bytes[](1);
        targets[0] = address(cbEthUsdc);
        datas[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newRheoImplementation), ""));
        _upgradeToV1_8_4(targets, datas);

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = shutdownCalldata;
        multicallData[1] = abi.encodeCall(IRheoAdmin.pause, ());

        vm.prank(owner);
        cbEthUsdc.multicall(multicallData);

        assertTrue(PausableUpgradeable(address(cbEthUsdc)).paused());
        DataView memory cbEthData = IRheoView(address(cbEthUsdc)).data();
        assertEq(cbEthData.debtToken.totalSupply(), 0);
        assertEq(cbEthData.collateralToken.totalSupply(), 0);

        assertFalse(PausableUpgradeable(address(wethUsdc)).paused());
        DataView memory wethUsdcData = IRheoView(address(wethUsdc)).data();
        assertEq(address(wethUsdcData.borrowTokenVault), address(borrowTokenVaultLocal));

        uint256 lendersToWithdraw = 1;
        for (uint256 i = 0; i < lendersToWithdraw; i++) {
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
