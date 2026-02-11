// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {IRheoV1_7} from "@rheo-fm/src/market/interfaces/v1.7/IRheoV1_7.sol";
import {IRheoV1_8} from "@rheo-fm/src/market/interfaces/v1.8/IRheoV1_8.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {ISizeFactoryV1_7} from "@rheo-solidity/src/factory/interfaces/ISizeFactoryV1_7.sol";
import {ISizeFactoryV1_8} from "@rheo-solidity/src/factory/interfaces/ISizeFactoryV1_8.sol";
import {Action, Authorization} from "@rheo-solidity/src/factory/libraries/Authorization.sol";

import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";
import {ERC4626_ADAPTER_ID} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {DepositOnBehalfOfParams, DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {
    SetCopyLimitOrderConfigsOnBehalfOfParams,
    SetCopyLimitOrderConfigsParams
} from "@rheo-fm/src/market/libraries/actions/SetCopyLimitOrderConfigs.sol";

import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {
    SellCreditMarketOnBehalfOfParams,
    SellCreditMarketParams
} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";
import {
    SetUserConfigurationOnBehalfOfParams,
    SetUserConfigurationParams
} from "@rheo-fm/src/market/libraries/actions/SetUserConfiguration.sol";
import {SetVaultOnBehalfOfParams, SetVaultParams} from "@rheo-fm/src/market/libraries/actions/SetVault.sol";
import {WithdrawOnBehalfOfParams, WithdrawParams} from "@rheo-fm/src/market/libraries/actions/Withdraw.sol";

import {BaseTest} from "@rheo-fm/test/BaseTest.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";

import {RheoMock} from "@rheo-fm/test/mocks/RheoMock.sol";

contract CallMarketTest is BaseTest {
    CopyLimitOrderConfig fullCopy = CopyLimitOrderConfig({
        minTenor: 0,
        maxTenor: type(uint256).max,
        minAPR: 0,
        maxAPR: type(uint256).max,
        offsetAPR: 0
    });

    function setUp() public override {
        super.setUp();
        _deployRheoMarket2();
    }

    function test_CallMarket_can_borrow_from_multiple_markets() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        size = size2;
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.04e18));
        size = size1;

        uint256 usdcBalanceBefore = usdc.balanceOf(bob);

        uint256 usdcAmount = 100e6;
        uint256 tenor = 150 days;
        uint256 maturity = block.timestamp + tenor;

        uint256 wethAmount = 300e18;
        uint256 collateral2Amount = 400e18;

        _mint(address(weth), bob, wethAmount);
        _mint(address(collateral2), bob, collateral2Amount);
        _approve(bob, address(weth), address(size1), wethAmount);
        _approve(bob, address(collateral2), address(size2), collateral2Amount);

        Action[] memory actions = new Action[](3);
        actions[0] = Action.DEPOSIT;
        actions[1] = Action.SELL_CREDIT_MARKET;
        actions[2] = Action.WITHDRAW;

        bytes[] memory datas = new bytes[](7);
        datas[0] = abi.encodeCall(
            ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.getActionsBitmap(actions))
        );
        datas[1] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size1),
                abi.encodeCall(
                    IRheoV1_7.depositOnBehalfOf,
                    (
                        DepositOnBehalfOfParams({
                            params: DepositParams({token: address(weth), amount: wethAmount, to: bob}),
                            onBehalfOf: bob
                        })
                    )
                )
            )
        );
        datas[2] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size1),
                abi.encodeCall(
                    IRheoV1_7.sellCreditMarketOnBehalfOf,
                    (
                        SellCreditMarketOnBehalfOfParams({
                            params: SellCreditMarketParams({
                                lender: alice,
                                creditPositionId: RESERVED_ID,
                                amount: usdcAmount,
                                maturity: maturity,
                                deadline: block.timestamp,
                                maxAPR: type(uint256).max,
                                exactAmountIn: false,
                                collectionId: RESERVED_ID,
                                rateProvider: address(0)
                            }),
                            onBehalfOf: bob,
                            recipient: bob
                        })
                    )
                )
            )
        );
        datas[3] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size2),
                abi.encodeCall(
                    IRheoV1_7.depositOnBehalfOf,
                    (
                        DepositOnBehalfOfParams({
                            params: DepositParams({token: address(collateral2), amount: collateral2Amount, to: bob}),
                            onBehalfOf: bob
                        })
                    )
                )
            )
        );
        datas[4] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size2),
                abi.encodeCall(
                    IRheoV1_7.sellCreditMarketOnBehalfOf,
                    (
                        SellCreditMarketOnBehalfOfParams({
                            params: SellCreditMarketParams({
                                lender: alice,
                                creditPositionId: RESERVED_ID,
                                amount: usdcAmount,
                                maturity: maturity,
                                deadline: block.timestamp,
                                maxAPR: type(uint256).max,
                                exactAmountIn: false,
                                collectionId: RESERVED_ID,
                                rateProvider: address(0)
                            }),
                            onBehalfOf: bob,
                            recipient: bob
                        })
                    )
                )
            )
        );
        datas[5] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size1),
                abi.encodeCall(
                    IRheoV1_7.withdrawOnBehalfOf,
                    (
                        WithdrawOnBehalfOfParams({
                            params: WithdrawParams({token: address(usdc), amount: type(uint256).max, to: bob}),
                            onBehalfOf: bob
                        })
                    )
                )
            )
        );
        datas[6] =
            abi.encodeCall(ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.nullActionsBitmap()));

        vm.startPrank(bob);
        MulticallUpgradeable(address(sizeFactory)).multicall(datas);

        assertEq(usdc.balanceOf(bob), usdcBalanceBefore + usdcAmount * 2);
    }

    function test_CallMarket_cannot_call_invalid_market() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.INVALID_MARKET.selector, address(alice)));
        sizeFactory.callMarket(
            address(alice),
            abi.encodeCall(IRheo.withdraw, (WithdrawParams({token: address(usdc), amount: 100e6, to: bob})))
        );
    }

    function test_CallMarket_can_copy_limit_orders_from_multiple_markets() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        size = size2;
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.04e18));
        size = size1;

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size1);
        _addMarketToCollection(james, collectionId, size2);
        _addRateProviderToCollectionMarket(james, collectionId, size1, alice);
        _addRateProviderToCollectionMarket(james, collectionId, size2, alice);

        uint256[] memory collectionIds = new uint256[](1);
        collectionIds[0] = collectionId;

        bytes[] memory datas = new bytes[](5);
        datas[0] = abi.encodeCall(
            ISizeFactoryV1_7.setAuthorization,
            (address(sizeFactory), Authorization.getActionsBitmap(Action.SET_COPY_LIMIT_ORDER_CONFIGS))
        );
        datas[1] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size1),
                abi.encodeCall(
                    IRheoV1_7.setCopyLimitOrderConfigsOnBehalfOf,
                    (
                        SetCopyLimitOrderConfigsOnBehalfOfParams({
                            params: SetCopyLimitOrderConfigsParams({
                                copyLoanOfferConfig: fullCopy,
                                copyBorrowOfferConfig: fullCopy
                            }),
                            onBehalfOf: bob
                        })
                    )
                )
            )
        );
        datas[2] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size2),
                abi.encodeCall(
                    IRheoV1_7.setCopyLimitOrderConfigsOnBehalfOf,
                    (
                        SetCopyLimitOrderConfigsOnBehalfOfParams({
                            params: SetCopyLimitOrderConfigsParams({
                                copyLoanOfferConfig: fullCopy,
                                copyBorrowOfferConfig: fullCopy
                            }),
                            onBehalfOf: bob
                        })
                    )
                )
            )
        );
        datas[3] =
            abi.encodeCall(ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.nullActionsBitmap()));
        datas[4] = abi.encodeCall(ISizeFactoryV1_8.subscribeToCollections, (collectionIds));

        vm.startPrank(bob);
        MulticallUpgradeable(address(sizeFactory)).multicall(datas);

        uint256 maturity = block.timestamp + 150 days;
        assertEq(size1.getLoanOfferAPR(bob, collectionId, alice, maturity), 0.03e18);
        assertEq(size2.getLoanOfferAPR(bob, collectionId, alice, maturity), 0.04e18);
    }

    function test_CallMarket_user_can_execute_ideal_flow() public {
        _setPrice(1e18);
        _deposit(alice, usdc, 500e6);

        size = size1;
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.03e18));
        size = size2;
        _buyCreditLimit(alice, block.timestamp + 150 days, _pointOfferAtIndex(4, 0.04e18));

        uint256 collectionId = _createCollection(james);
        _addMarketToCollection(james, collectionId, size1);
        _addMarketToCollection(james, collectionId, size2);
        _addRateProviderToCollectionMarket(james, collectionId, size1, alice);
        _addRateProviderToCollectionMarket(james, collectionId, size2, alice);

        uint256[] memory collectionIds = new uint256[](1);
        collectionIds[0] = collectionId;

        _setVaultAdapter(vaultOpenZeppelin, ERC4626_ADAPTER_ID);

        uint256 depositAmount = 100e6;

        _mint(address(usdc), candy, depositAmount);

        Action[] memory actions = new Action[](3);
        actions[0] = Action.SET_VAULT;
        actions[1] = Action.DEPOSIT;
        actions[2] = Action.SET_COPY_LIMIT_ORDER_CONFIGS;

        bytes[] memory datas = new bytes[](5);
        datas[0] = abi.encodeCall(
            ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.getActionsBitmap(actions))
        );
        datas[1] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size1),
                abi.encodeCall(
                    IRheoV1_8.setVaultOnBehalfOf,
                    (
                        SetVaultOnBehalfOfParams({
                            params: SetVaultParams({vault: address(vaultOpenZeppelin), forfeitOldShares: false}),
                            onBehalfOf: candy
                        })
                    )
                )
            )
        );
        datas[2] = abi.encodeCall(
            ISizeFactoryV1_8.callMarket,
            (
                address(size1),
                abi.encodeCall(
                    IRheoV1_7.depositOnBehalfOf,
                    (
                        DepositOnBehalfOfParams({
                            params: DepositParams({token: address(usdc), amount: depositAmount, to: candy}),
                            onBehalfOf: candy
                        })
                    )
                )
            )
        );
        datas[3] = abi.encodeCall(ISizeFactoryV1_8.subscribeToCollections, (collectionIds));
        datas[4] =
            abi.encodeCall(ISizeFactoryV1_7.setAuthorization, (address(sizeFactory), Authorization.nullActionsBitmap()));

        vm.prank(candy);
        usdc.approve(address(size1), depositAmount);
        vm.prank(candy);
        MulticallUpgradeable(address(sizeFactory)).multicall(datas);

        assertEq(_state().candy.borrowTokenBalance, depositAmount);
        uint256 maturity = block.timestamp + 150 days;
        assertEq(size1.getLoanOfferAPR(candy, collectionId, alice, maturity), 0.03e18);
        assertEq(size2.getLoanOfferAPR(candy, collectionId, alice, maturity), 0.04e18);
    }
}
