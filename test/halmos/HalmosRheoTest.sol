// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import "halmos-helpers-lib/HalmosHelpers.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IRheoFactory} from "@rheo-fm/src/factory-compat/interfaces/IRheoFactory.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {Action, Authorization} from "@rheo-solidity/src/factory/libraries/Authorization.sol";
import {MockERC4626 as ERC4626Solady} from "@solady/test/utils/mocks/MockERC4626.sol";

import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {
    Initialize,
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {ERC4626Adapter} from "@rheo-fm/src/market/token/adapters/ERC4626Adapter.sol";
import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";
import "@rheo-fm/test/mocks/NonTransferrableRebasingTokenVaultMock.sol";
import "@rheo-fm/test/mocks/PoolMock.sol";
import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";
import "@rheo-fm/test/mocks/USDC.sol";

import {WETH} from "@rheo-fm/test/mocks/WETH.sol";

import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {AaveAdapter} from "@rheo-fm/src/market/token/adapters/AaveAdapter.sol";

contract HalmosRheoTest is Test, HalmosHelpers {
    uint256 private constant USDC_INITIAL_BALANCE = 1_000_000e6;
    address deployer = address(0xcafe0000);
    address feeRecipient = address(0xcafe0001);

    ISizeFactory internal sizeFactory;
    address internal implementation;
    IERC20Metadata internal collateral;
    PriceFeedMock internal priceFeed;
    InitializeFeeConfigParams internal f;
    InitializeRiskConfigParams internal r;
    InitializeOracleParams internal o;
    InitializeDataParams internal d;
    USDC private usdc;
    WETH internal weth;
    ERC4626Adapter erc4626Adapter;
    IERC4626 internal vaultSolady;
    ERC1967Proxy internal proxy;
    AaveAdapter private aaveAdapter;

    Rheo internal size;
    NonTransferrableRebasingTokenVaultMock private token;
    IPool private variablePool;

    SymbolicActor[] vaults;
    SymbolicActor[] actors;

    address alice;
    address bob;

    address symbolic_vault;

    constructor() {}

    function setUp() external {
        settingUp();
    }

    function settingUp() internal {
        vm.startPrank(getConfigurer());
        halmosHelpersInitialize();
        // Don't process callbacks symbolically during setup
        halmosHelpersSetSymbolicCallbacksDepth(0, 0);
        /*
        * Initialize 2 Actors
        * actors[0] is a regular user
        * actors[1] is a regular user
        */
        actors = halmosHelpersGetSymbolicActorArray(2);
        /* vault can have any implementation. Therefore we use a symbolic handler as a vault */
        vaults = halmosHelpersGetSymbolicActorArray(1);

        alice = address(actors[0]);
        bob = address(actors[1]);
        symbolic_vault = address(vaults[0]);

        vm.stopPrank();

        vm.startPrank(deployer);

        collateral = IERC20Metadata(address(new ERC20Mock()));
        priceFeed = new PriceFeedMock(deployer);
        priceFeed.setPrice(1e18);
        weth = new WETH();
        usdc = new USDC(deployer);
        usdc.mint(address(alice), USDC_INITIAL_BALANCE);
        usdc.mint(address(bob), USDC_INITIAL_BALANCE);
        variablePool = IPool(address(new PoolMock()));

        token = new NonTransferrableRebasingTokenVaultMock();
        sizeFactory = ISizeFactory(
            address(new ERC1967Proxy(address(new SizeFactory()), abi.encodeCall(SizeFactory.initialize, (deployer))))
        );
        token.initialize(
            IRheoFactory(address(sizeFactory)),
            variablePool,
            usdc,
            address(deployer),
            string.concat("Rheo ", usdc.name(), " Vault"),
            string.concat("sv", usdc.symbol()),
            usdc.decimals()
        );

        f = InitializeFeeConfigParams({
            swapFeeAPR: 0.005e18,
            fragmentationFee: 5e6,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.01e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: feeRecipient
        });
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = 30 days;
        maturities[1] = 60 days;
        r = InitializeRiskConfigParams({
            crOpening: 1.5e18,
            crLiquidation: 1.3e18,
            minimumCreditBorrowToken: 5e6,
            minTenor: 30 days,
            maxTenor: 60 days,
            maturities: maturities
        });
        o = InitializeOracleParams({priceFeed: address(priceFeed)});
        d = InitializeDataParams({
            weth: address(weth),
            underlyingCollateralToken: address(weth),
            underlyingBorrowToken: address(usdc),
            variablePool: address(variablePool), // Aave v3
            borrowTokenVault: address(token),
            sizeFactory: address(sizeFactory)
        });

        implementation = address(new Rheo());
        sizeFactory.setRheoImplementation(implementation);
        InitializeFeeConfigParams memory feeConfigParams = f;
        InitializeRiskConfigParams memory riskConfigParams = r;
        InitializeOracleParams memory oracleParams = o;
        InitializeDataParams memory dataParams = d;
        proxy = ERC1967Proxy(
            payable(sizeFactory.createMarketRheo(feeConfigParams, riskConfigParams, oracleParams, dataParams))
        );
        size = Rheo(payable(proxy));
        PriceFeedMock(address(priceFeed)).setPrice(1337e18);

        erc4626Adapter = new ERC4626Adapter(token);
        token.setAdapter(bytes32("ERC4626Adapter"), erc4626Adapter);
        aaveAdapter = new AaveAdapter(token);
        token.setAdapter(bytes32("AaveAdapter"), aaveAdapter);
        token.setVaultAdapter(DEFAULT_VAULT, bytes32("AaveAdapter"));
        token.setVaultAdapter(symbolic_vault, bytes32("ERC4626Adapter"));
        vaultSolady = IERC4626(address(new ERC4626Solady(address(usdc), "VaultSolady", "VAULTSOLADY", true, 0)));
        token.setVaultAdapter(address(vaultSolady), bytes32("ERC4626Adapter"));

        vm.stopPrank();

        vm.startPrank(address(size));
        token.setVault(alice, symbolic_vault, false);
        token.setVault(bob, address(vaultSolady), false);
        vm.stopPrank();

        /* 
        * Deposit something and leave something on actors' balances, while everything is approved
        * to cover more scenarios 
        */
        vm.startPrank(alice);
        usdc.approve(address(size), USDC_INITIAL_BALANCE);
        size.deposit(DepositParams({token: address(usdc), amount: USDC_INITIAL_BALANCE / 2, to: alice}));
        sizeFactory.setAuthorization(address(size), Authorization.getActionsBitmap(Action.SET_USER_CONFIGURATION));
        sizeFactory.setAuthorization(symbolic_vault, Authorization.getActionsBitmap(Action.SET_USER_CONFIGURATION));
        vm.stopPrank();
        // Symbolic implementation of vault can "forget" to take approved assets
        vm.prank(address(vaults[0]));
        usdc.transferFrom(address(erc4626Adapter), address(symbolic_vault), USDC_INITIAL_BALANCE / 2);

        vm.startPrank(bob);
        usdc.approve(address(size), USDC_INITIAL_BALANCE);
        size.deposit(DepositParams({token: address(usdc), amount: USDC_INITIAL_BALANCE / 2, to: bob}));
        sizeFactory.setAuthorization(address(size), Authorization.getActionsBitmap(Action.SET_USER_CONFIGURATION));
        vm.stopPrank();

        vm.startPrank(getConfigurer());
        halmosHelpersRegisterTargetAddress(address(size), "Rheo");
        /* 
        * heuristics: multicall causes path explosion and doesn't create any new coverage.
        * So I've decided to exclude this function from invariant testing.
        * TODO: enable this selector when halmos-helpers will support optimized delegatecalls handling
        */
        halmosHelpersBanFunctionSelector(size.multicall.selector);
        vm.stopPrank();
    }

    /* Should find 3.1.1 (No reentrancy required) */
    function check_BalanceIntegrityNoReentrancy() external {
        //vm.startPrank(getConfigurer());
        // halmosHelpersSetOnlyAllowedSelectors(true);
        // halmosHelpersAllowFunctionSelector(size.setUserConfigurationOnBehalfOf.selector);
        //vm.stopPrank();

        halmosHelpersSymbolicBatchStartPrank(actors);
        executeSymbolicallyAllTargets("check_balanceIntegrityRheo");
        vm.stopPrank();

        vaultSoladyBalanceNotBrokenInvarint();
    }

    /* Should find 3.1.1 and 3.3.2. Long test */
    function check_BalanceIntegrityWithReentrancyNoDuplicateCallsDisabled() external {
        vm.startPrank(getConfigurer());
        // halmosHelpersSetOnlyAllowedSelectors(true);
        // halmosHelpersAllowFunctionSelector(size.deposit.selector);
        // halmosHelpersAllowFunctionSelector(size.setUserConfigurationOnBehalfOf.selector);
        /* Process callbacks of depth 1 */
        halmosHelpersSetSymbolicCallbacksDepth(1, 1);
        vm.stopPrank();

        halmosHelpersSymbolicBatchStartPrank(actors);
        executeSymbolicallyAllTargets("check_balanceIntegrityRheo");
        vm.stopPrank();

        vaultSoladyBalanceNotBrokenInvarint();
    }

    /* Should find 3.1.1 and 3.3.2. Test is still pretty long but shorter than check_BalanceIntegrityWithReentrancyNoDuplicateCallsDisabled */
    function check_BalanceIntegrityWithReentrancyNoDuplicateCallsEnabled() external {
        vm.startPrank(getConfigurer());
        //halmosHelpersSetOnlyAllowedSelectors(true);
        //halmosHelpersAllowFunctionSelector(size.deposit.selector);
        //halmosHelpersAllowFunctionSelector(size.setUserConfigurationOnBehalfOf.selector);

        /* Process callbacks of depth 1 */
        halmosHelpersSetSymbolicCallbacksDepth(1, 1);
        halmosHelpersSetNoDuplicateCalls(true);
        vm.stopPrank();

        halmosHelpersSymbolicBatchStartPrank(actors);
        executeSymbolicallyAllTargets("check_balanceIntegrityRheo");
        vm.stopPrank();

        vaultSoladyBalanceNotBrokenInvarint();
    }

    /* 
    * Theoretically, this test should find 3.1.1 and 3.3.2 in all forms (via reentrancy and trivially) in some time. 
    * However, given that we have a lot of targets, there is no certainty that this test will be completed even in six months.
    * It is also necessary to investigate all symbolic execution bottlenecks in these contracts and handle them.
    * It should be perceived as just a way to expand the scenarios for testing, not an actual test to run.
    */
    function check_BalanceIntegrityFull() external {
        vm.startPrank(getConfigurer());
        halmosHelpersSetSymbolicCallbacksDepth(2, 2);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i].setSymbolicFallbackTxsNumber(2);
            actors[i].setSymbolicReceiveTxsNumber(2);
        }
        for (uint256 i = 0; i < vaults.length; i++) {
            actors[i].setSymbolicFallbackTxsNumber(2);
            actors[i].setSymbolicReceiveTxsNumber(2);
        }
        halmosHelpersRegisterTargetAddress(address(collateral), "ERC20Mock");
        halmosHelpersRegisterTargetAddress(address(priceFeed), "PriceFeedMock");
        halmosHelpersRegisterTargetAddress(address(weth), "ERC20Mock");
        halmosHelpersRegisterTargetAddress(address(usdc), "WETH");
        halmosHelpersRegisterTargetAddress(address(variablePool), "IPool");
        halmosHelpersRegisterTargetAddress(address(token), "NonTransferrableRebasingTokenVault");
        halmosHelpersRegisterTargetAddress(address(sizeFactory), "RheoFactory");
        halmosHelpersRegisterTargetAddress(address(implementation), "Rheo");
        halmosHelpersRegisterTargetAddress(address(erc4626Adapter), "ERC4626Adapter");
        halmosHelpersRegisterTargetAddress(address(aaveAdapter), "AaveAdapter");
        halmosHelpersRegisterTargetAddress(address(vaultSolady), "IERC4626");
        halmosHelpersRegisterTargetAddress(symbolic_vault, "SymbolicActor");
        halmosHelpersRegisterTargetAddress(address(proxy), "ERC1967Proxy");
        halmosHelpersRegisterTargetAddress(address(collateral), "ERC20Mock");

        vm.stopPrank();

        halmosHelpersSymbolicBatchStartPrank(actors);
        executeSymbolicallyAllTargets("check_balanceIntegrityFull_1");
        vm.stopPrank();

        halmosHelpersSymbolicBatchStartPrank(actors);
        executeSymbolicallyAllTargets("check_balanceIntegrityFull_2");
        vm.stopPrank();

        vaultSoladyBalanceNotBrokenInvarint();
    }

    function vaultSoladyBalanceNotBrokenInvarint() internal view {
        /* A regular vault should be able to return all assets */
        assert(token.getAllShares(address(vaultSolady)) <= usdc.balanceOf(address(vaultSolady)));
    }

    function check_marketCanSetValidVault() external {
        bool res;
        bytes memory retdata;

        halmosHelpersSymbolicBatchStartPrank(actors);
        executeSymbolicallyAllTargets("check_balanceIntegrity");
        vm.stopPrank();

        /* market should be able to change vault for any valid user */
        address user = _svm.createAddress("user");
        vm.assume(user != address(0x0));
        vm.assume(token.vaultOf(user) != address(vaultSolady));
        bool forfeitOldShares = true;
        bytes memory setVault_calldata =
            abi.encodeWithSelector(token.setVault.selector, user, address(vaultSolady), forfeitOldShares);

        vm.prank(address(size));
        (res, retdata) = address(token).call(setVault_calldata);

        assert(res == true);
    }
}
