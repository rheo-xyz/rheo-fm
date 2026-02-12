// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";
import {DataView} from "@rheo-fm/src/market/RheoViewData.sol";

import {WadRayMath} from "@aave/protocol/libraries/math/WadRayMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@crytic/properties/contracts/util/Hevm.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Math} from "@rheo-fm/src/market/libraries/Math.sol";
import {PoolMock} from "@rheo-fm/test/mocks/PoolMock.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

import {PriceFeed, PriceFeedParams} from "@rheo-fm/src/oracle/v1.5.1/PriceFeed.sol";

import {PriceFeedMock} from "@rheo-fm/test/mocks/PriceFeedMock.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {
    AAVE_ADAPTER_ID,
    DEFAULT_VAULT,
    ERC4626_ADAPTER_ID
} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {AaveAdapter} from "@rheo-fm/src/market/token/adapters/AaveAdapter.sol";
import {ERC4626Adapter} from "@rheo-fm/src/market/token/adapters/ERC4626Adapter.sol";

import {NetworkConfiguration} from "@rheo-fm/script/Networks.sol";
import {
    Initialize,
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";
import {SizeFactory} from "@rheo-fm/src/factory/SizeFactory.sol";

import {RheoMock} from "@rheo-fm/test/mocks/RheoMock.sol";
import {USDC} from "@rheo-fm/test/mocks/USDC.sol";
import {WETH} from "@rheo-fm/test/mocks/WETH.sol";

import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {NonTransferrableRebasingTokenVaultGhost} from "@rheo-fm/test/mocks/NonTransferrableRebasingTokenVaultGhost.sol";
import {IRheoFactory} from "@rheo-fm/src/factory/interfaces/IRheoFactory.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {ERC4626Mock as ERC4626OpenZeppelin} from "@openzeppelin/contracts/mocks/token/ERC4626Mock.sol";
import {MockERC4626 as ERC4626Solady} from "@solady/test/utils/mocks/MockERC4626.sol";
import {MockERC4626 as ERC4626Solmate} from "@solmate/src/test/utils/mocks/MockERC4626.sol";
import {ERC20 as ERC20Solmate} from "@solmate/src/tokens/ERC20.sol";

import {ControlledAsyncDeposit} from "@ERC-7540-Reference/src/ControlledAsyncDeposit.sol";
import {ControlledAsyncRedeem} from "@ERC-7540-Reference/src/ControlledAsyncRedeem.sol";
import {FullyAsyncVault} from "@ERC-7540-Reference/src/FullyAsyncVault.sol";

import {FeeOnEntryExitERC4626} from "@rheo-fm/test/mocks/vaults/FeeOnEntryExitERC4626.sol";
import {FeeOnTransferERC4626} from "@rheo-fm/test/mocks/vaults/FeeOnTransferERC4626.sol";
import {LimitsERC4626} from "@rheo-fm/test/mocks/vaults/LimitsERC4626.sol";

import {MaliciousERC4626Reentrancy} from "@rheo-fm/test/mocks/vaults/MaliciousERC4626Reentrancy.sol";
import {MaliciousERC4626ReentrancyGeneric} from "@rheo-fm/test/mocks/vaults/MaliciousERC4626ReentrancyGeneric.sol";
import {MaliciousERC4626WithdrawNotAllowed} from "@rheo-fm/test/mocks/vaults/MaliciousERC4626WithdrawNotAllowed.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";

abstract contract Deploy {
    address internal implementation;
    ERC1967Proxy internal proxy;
    RheoMock internal size;
    IPriceFeed internal priceFeed;
    WETH internal weth;
    USDC internal usdc;
    IPool internal variablePool;
    InitializeFeeConfigParams internal f;
    InitializeRiskConfigParams internal r;
    InitializeOracleParams internal o;
    InitializeDataParams internal d;

    IERC20Metadata internal collateralToken;
    IERC20Metadata internal borrowToken;

    IRheoFactory internal sizeFactory;
    CollectionsManager internal collectionsManager;

    bool internal shouldDeploySizeFactory = true;

    IERC4626 internal vaultSolady;
    IERC4626 internal vaultOpenZeppelin;
    IERC4626 internal vaultSolmate;
    IERC4626 internal vaultMaliciousWithdrawNotAllowed;
    IERC4626 internal vaultMaliciousReentrancy;
    IERC4626 internal vaultMaliciousReentrancyGeneric;
    IERC4626 internal vaultFeeOnTransfer;
    IERC4626 internal vaultFeeOnEntryExit;
    IERC4626 internal vaultLimits;
    IERC4626 internal vaultNonERC4626;
    IERC4626 internal vaultERC7540FullyAsync;
    IERC4626 internal vaultERC7540ControlledAsyncDeposit;
    IERC4626 internal vaultERC7540ControlledAsyncRedeem;
    IERC4626 internal vaultInvalidUnderlying;

    RheoMock internal size1;
    RheoMock internal size2;
    PriceFeedMock internal priceFeed2;
    IERC20Metadata internal collateral2;

    uint256 internal constant INITIAL_BLOCK_TIME = 1830297600; // 2028-01-01T00:00:00.000Z
    uint256 private constant TIMELOCK = 24 hours;

    function _defaultRiskMaturities() internal view returns (uint256[] memory maturities) {
        maturities = new uint256[](6);
        for (uint256 i = 0; i < maturities.length; i++) {
            maturities[i] = block.timestamp + (i + 1) * 30 days;
        }
    }

    function setupLocal(address owner, address feeRecipient) internal {
        hevm.warp(INITIAL_BLOCK_TIME);
        priceFeed = new PriceFeedMock(owner);
        weth = new WETH();
        usdc = new USDC(owner);
        variablePool = IPool(address(new PoolMock()));
        PoolMock(address(variablePool)).setLiquidityIndex(address(weth), WadRayMath.RAY);
        PoolMock(address(variablePool)).setLiquidityIndex(address(usdc), WadRayMath.RAY);

        if (shouldDeploySizeFactory) {
            sizeFactory = IRheoFactory(
                address(new ERC1967Proxy(address(new SizeFactory()), abi.encodeCall(SizeFactory.initialize, (owner))))
            );

            collectionsManager = CollectionsManager(
                address(
                    new ERC1967Proxy(
                        address(new CollectionsManager()), abi.encodeCall(CollectionsManager.initialize, sizeFactory)
                    )
                )
            );
            hevm.prank(owner);
            SizeFactory(payable(address(sizeFactory))).setCollectionsManager(address(collectionsManager));
        }

        address borrowTokenVaultImplementation = address(new NonTransferrableRebasingTokenVaultGhost());

        _deployVaults();

        hevm.prank(owner);
        sizeFactory.setNonTransferrableRebasingTokenVaultImplementation(borrowTokenVaultImplementation);

        hevm.prank(owner);
        NonTransferrableRebasingTokenVault borrowTokenVault =
            NonTransferrableRebasingTokenVault(address(sizeFactory.createBorrowTokenVault(variablePool, usdc)));

        AaveAdapter aaveAdapter = new AaveAdapter(borrowTokenVault);
        hevm.prank(owner);
        borrowTokenVault.setAdapter(AAVE_ADAPTER_ID, aaveAdapter);
        hevm.prank(owner);
        borrowTokenVault.setVaultAdapter(DEFAULT_VAULT, AAVE_ADAPTER_ID);

        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(borrowTokenVault);
        hevm.prank(owner);
        borrowTokenVault.setAdapter(ERC4626_ADAPTER_ID, erc4626Adapter);

        f = InitializeFeeConfigParams({
            swapFeeAPR: 0.005e18,
            fragmentationFee: 5e6,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.01e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: feeRecipient
        });
        r = InitializeRiskConfigParams({
            crOpening: 1.5e18,
            crLiquidation: 1.3e18,
            minimumCreditBorrowToken: 5e6,
            minTenor: 1 hours,
            maxTenor: 5 * 365 days,
            maturities: _defaultRiskMaturities()
        });
        o = InitializeOracleParams({priceFeed: address(priceFeed)});
        d = InitializeDataParams({
            weth: address(weth),
            underlyingCollateralToken: address(weth),
            underlyingBorrowToken: address(usdc),
            variablePool: address(variablePool), // Aave v3
            borrowTokenVault: address(borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });

        implementation = address(new RheoMock());
        hevm.prank(owner);
        sizeFactory.setRheoImplementation(implementation);

        hevm.prank(owner);
        proxy = ERC1967Proxy(payable(_createMarketRheoFromStorage()));
        size = RheoMock(payable(proxy));

        hevm.prank(owner);
        PriceFeedMock(address(priceFeed)).setPrice(1337e18);
    }

    function setupLocalGenericMarket(
        address owner,
        address feeRecipient,
        uint256 collateralTokenPriceUSD,
        uint256 borrowTokenPriceUSD,
        uint8 collateralTokenDecimals,
        uint8 borrowTokenDecimals,
        bool collateralTokenIsWETH,
        bool borrowTokenIsWETH
    ) internal {
        hevm.warp(INITIAL_BLOCK_TIME);
        priceFeed = new PriceFeedMock(owner);
        uint256 price = Math.mulDivDown(collateralTokenPriceUSD, 10 ** priceFeed.decimals(), borrowTokenPriceUSD);

        weth = new WETH();
        collateralToken = IERC20Metadata(address(new MockERC20("CollateralToken", "CTK", collateralTokenDecimals)));
        borrowToken = IERC20Metadata(address(new MockERC20("BorrowToken", "BTK", borrowTokenDecimals)));
        if (collateralTokenIsWETH) {
            collateralToken = IERC20Metadata(address(weth));
        }
        if (borrowTokenIsWETH) {
            borrowToken = IERC20Metadata(address(weth));
        }

        variablePool = IPool(address(new PoolMock()));
        PoolMock(address(variablePool)).setLiquidityIndex(address(borrowToken), 1.234567e27);

        if (shouldDeploySizeFactory) {
            sizeFactory = IRheoFactory(
                address(new ERC1967Proxy(address(new SizeFactory()), abi.encodeCall(SizeFactory.initialize, (owner))))
            );

            collectionsManager = CollectionsManager(
                address(
                    new ERC1967Proxy(
                        address(new CollectionsManager()), abi.encodeCall(CollectionsManager.initialize, sizeFactory)
                    )
                )
            );
            hevm.prank(owner);
            SizeFactory(payable(address(sizeFactory))).setCollectionsManager(address(collectionsManager));
        }

        address borrowTokenVaultImplementation = address(new NonTransferrableRebasingTokenVaultGhost());

        hevm.prank(owner);
        sizeFactory.setNonTransferrableRebasingTokenVaultImplementation(borrowTokenVaultImplementation);

        hevm.prank(owner);
        NonTransferrableRebasingTokenVault borrowTokenVault =
            NonTransferrableRebasingTokenVault(address(sizeFactory.createBorrowTokenVault(variablePool, borrowToken)));

        AaveAdapter aaveAdapter = new AaveAdapter(borrowTokenVault);
        hevm.prank(owner);
        borrowTokenVault.setAdapter(AAVE_ADAPTER_ID, aaveAdapter);
        hevm.prank(owner);
        borrowTokenVault.setVaultAdapter(DEFAULT_VAULT, AAVE_ADAPTER_ID);

        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(borrowTokenVault);
        hevm.prank(owner);
        borrowTokenVault.setAdapter(ERC4626_ADAPTER_ID, erc4626Adapter);

        f = InitializeFeeConfigParams({
            swapFeeAPR: 0.005e18,
            fragmentationFee: Math.mulDivDown(
                5 * 10 ** borrowToken.decimals(), 10 ** priceFeed.decimals(), borrowTokenPriceUSD
            ),
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.01e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: feeRecipient
        });
        r = InitializeRiskConfigParams({
            crOpening: 1.5e18,
            crLiquidation: 1.3e18,
            minimumCreditBorrowToken: Math.mulDivDown(
                10 * 10 ** borrowToken.decimals(), 10 ** priceFeed.decimals(), borrowTokenPriceUSD
            ),
            minTenor: 1 hours,
            maxTenor: 5 * 365 days,
            maturities: _defaultRiskMaturities()
        });
        o = InitializeOracleParams({priceFeed: address(priceFeed)});
        d = InitializeDataParams({
            weth: address(weth),
            underlyingCollateralToken: address(collateralToken),
            underlyingBorrowToken: address(borrowToken),
            variablePool: address(variablePool),
            borrowTokenVault: address(borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });

        implementation = address(new RheoMock());
        hevm.prank(owner);
        sizeFactory.setRheoImplementation(implementation);

        hevm.prank(owner);
        proxy = ERC1967Proxy(payable(_createMarketRheoFromStorage()));
        size = RheoMock(payable(proxy));

        hevm.prank(owner);
        PriceFeedMock(address(priceFeed)).setPrice(price);
    }

    function setupFork(address _size, address _priceFeed, address _variablePool, address _weth, address _usdc)
        internal
    {
        size = RheoMock(_size);
        priceFeed = IPriceFeed(_priceFeed);
        variablePool = IPool(_variablePool);
        weth = WETH(payable(_weth));
        usdc = USDC(_usdc);
    }

    function _deployVaults() internal {
        vaultSolady = IERC4626(address(new ERC4626Solady(address(usdc), "VaultSolady", "VAULTSOLADY", true, 0)));
        vaultOpenZeppelin = IERC4626(address(new ERC4626OpenZeppelin(address(usdc))));
        vaultSolmate =
            IERC4626(address(new ERC4626Solmate(ERC20Solmate(address(usdc)), "VaultSolmate", "VAULTSOLMATE")));
        vaultMaliciousWithdrawNotAllowed = IERC4626(
            address(
                new MaliciousERC4626WithdrawNotAllowed(
                    usdc, "VaultMaliciousWithdrawNotAllowed", "VAULTMALICIOUSWITHDRAWNOTALLOWED"
                )
            )
        );
        vaultMaliciousReentrancy = IERC4626(address(new MaliciousERC4626Reentrancy(address(usdc))));
        vaultMaliciousReentrancyGeneric = IERC4626(
            address(
                new MaliciousERC4626ReentrancyGeneric(
                    usdc, "VaultMaliciousReentrancyGeneric", "VAULTMALICIOUSREENTRANCYGENERIC"
                )
            )
        );
        vaultFeeOnTransfer =
            IERC4626(address(new FeeOnTransferERC4626(usdc, "VaultFeeOnTransfer", "VAULTFEEONTXFER", 0.1e18)));
        vaultFeeOnEntryExit = IERC4626(
            address(new FeeOnEntryExitERC4626(usdc, "VaultFeeOnEntryExit", "VAULTFEEONENTRYEXIT", 0.1e4, 0.2e4))
        );
        vaultLimits = IERC4626(
            address(
                new LimitsERC4626(address(this), usdc, "VaultLimits", "VAULTLIMITS", 1000e6, 2000e6, 3000e6, 4000e6)
            )
        );
        vaultNonERC4626 = IERC4626(address(new ERC20Mock()));
        vaultERC7540FullyAsync =
            IERC4626(address(new FullyAsyncVault(ERC20Solmate(address(usdc)), "VaultERC7540", "VAULTERC7540")));
        vaultERC7540ControlledAsyncDeposit =
            IERC4626(address(new ControlledAsyncDeposit(ERC20Solmate(address(usdc)), "VaultERC7540", "VAULTERC7540")));
        vaultERC7540ControlledAsyncRedeem =
            IERC4626(address(new ControlledAsyncRedeem(ERC20Solmate(address(usdc)), "VaultERC7540", "VAULTERC7540")));
        vaultInvalidUnderlying = IERC4626(
            address(new ERC4626Solady(address(weth), "VaultInvalidUnderlying", "VAULTINVALIDUNDERLYING", true, 0))
        );
    }

    function _deployRheoMarket2() internal {
        collateral2 = IERC20Metadata(address(new ERC20Mock()));
        priceFeed2 = new PriceFeedMock(address(this));
        priceFeed2.setPrice(1e18);

        IRheo market = IRheo(sizeFactory.getMarket(0));
        InitializeFeeConfigParams memory feeConfigParams = market.feeConfig();

        InitializeRiskConfigParams memory riskConfigParams = market.riskConfig();
        riskConfigParams.crOpening = 1.12e18;
        riskConfigParams.crLiquidation = 1.09e18;

        InitializeOracleParams memory oracleParams = market.oracle();
        oracleParams.priceFeed = address(priceFeed2);

        DataView memory dataView = market.data();
        InitializeDataParams memory dataParams = InitializeDataParams({
            weth: address(weth),
            underlyingCollateralToken: address(collateral2),
            underlyingBorrowToken: address(dataView.underlyingBorrowToken),
            variablePool: address(dataView.variablePool),
            borrowTokenVault: address(dataView.borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });
        size2 = RheoMock(_createMarketRheo(feeConfigParams, riskConfigParams, oracleParams, dataParams));
        size1 = size;

        hevm.label(address(size1), "Rheo1");
        hevm.label(address(size2), "Rheo2");
    }

    function _createMarketRheoFromStorage() internal returns (address market) {
        InitializeFeeConfigParams memory feeConfigParams = f;
        InitializeRiskConfigParams memory riskConfigParams = r;
        InitializeOracleParams memory oracleParams = o;
        InitializeDataParams memory dataParams = d;
        market = _createMarketRheo(feeConfigParams, riskConfigParams, oracleParams, dataParams);
    }

    function _createMarketRheo(
        InitializeFeeConfigParams memory feeConfigParams,
        InitializeRiskConfigParams memory riskConfigParams,
        InitializeOracleParams memory oracleParams,
        InitializeDataParams memory dataParams
    ) internal returns (address market) {
        market = sizeFactory.createMarketRheo(feeConfigParams, riskConfigParams, oracleParams, dataParams);
    }
}
