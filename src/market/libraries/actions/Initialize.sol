// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";
import {IPool} from "@aave/interfaces/IPool.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IWETH} from "@rheo-fm/src/market/interfaces/IWETH.sol";

import {Math, PERCENT, YEAR} from "@rheo-fm/src/market/libraries/Math.sol";

import {CREDIT_POSITION_ID_START, DEBT_POSITION_ID_START} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

import {IPriceFeed} from "@rheo-fm/src/oracle/IPriceFeed.sol";

import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";
import {NonTransferrableToken} from "@rheo-fm/src/market/token/NonTransferrableToken.sol";

import {CollateralAsset, MAX_COLLATERAL_ASSETS, State} from "@rheo-fm/src/market/RheoStorage.sol";

import {PRICE_FEED_DECIMALS} from "@rheo-fm/src/market/libraries/CollateralBasketLibrary.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {Events} from "@rheo-fm/src/market/libraries/Events.sol";

// See RheoStorage.sol for the definitions of the structs below
struct InitializeFeeConfigParams {
    uint256 swapFeeAPR;
    uint256 fragmentationFee;
    uint256 liquidationRewardPercent;
    uint256 overdueCollateralProtocolPercent;
    uint256 collateralProtocolPercent;
    address feeRecipient;
}

struct InitializeRiskConfigParams {
    uint256 crOpening;
    uint256 crLiquidation;
    uint256 minimumCreditBorrowToken;
    uint256 minTenor;
    uint256 maxTenor;
    uint256[] maturities;
}

/// @dev DEPRECATED in v2.0: no longer part of `initialize`, kept so the `oracle()` view can keep reporting
///      the price feed of the first collateral asset
struct InitializeOracleParams {
    address priceFeed;
}

struct InitializeCollateralAssetParams {
    address underlying;
    address priceFeed;
    uint256 cap;
}

struct InitializeDataParams {
    address weth;
    InitializeCollateralAssetParams[] collateralAssets;
    address underlyingBorrowToken;
    address variablePool;
    address borrowTokenVault;
    address sizeFactory;
}

/// @title Initialize
/// @custom:security-contact security@rheo.xyz
/// @author Rheo (https://rheo.xyz/)
/// @notice Contains the logic to initialize the protocol
/// @dev The collateralToken (e.g. szETH) and debtToken (e.g. szDebt) are created in the `executeInitialize` function
///      The borrowTokenVault (e.g. svUSDC) must have been deployed before the initialization
library Initialize {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Validates the owner address
    /// @param owner The owner address
    function validateOwner(address owner) internal pure {
        if (owner == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
    }

    /// @notice Validates the parameters for the fee configuration
    /// @param f The fee configuration parameters
    function validateInitializeFeeConfigParams(InitializeFeeConfigParams memory f) internal pure {
        // validate swapFeeAPR
        // N/A

        // validate fragmentationFee
        // N/A

        // validate liquidationRewardPercent
        if (f.liquidationRewardPercent > PERCENT) {
            revert Errors.INVALID_AMOUNT(f.liquidationRewardPercent);
        }

        // validate overdueCollateralProtocolPercent
        if (f.overdueCollateralProtocolPercent > PERCENT) {
            revert Errors.INVALID_COLLATERAL_PERCENTAGE_PREMIUM(f.overdueCollateralProtocolPercent);
        }

        // validate collateralProtocolPercent
        if (f.collateralProtocolPercent > PERCENT) {
            revert Errors.INVALID_COLLATERAL_PERCENTAGE_PREMIUM(f.collateralProtocolPercent);
        }

        // validate feeRecipient
        if (f.feeRecipient == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
    }

    /// @notice Validates the parameters for the risk configuration
    /// @param r The risk configuration parameters
    function validateInitializeRiskConfigParams(InitializeRiskConfigParams memory r) internal pure {
        // validate crOpening
        if (r.crOpening < PERCENT) {
            revert Errors.INVALID_COLLATERAL_RATIO(r.crOpening);
        }

        // validate crLiquidation
        if (r.crLiquidation < PERCENT) {
            revert Errors.INVALID_COLLATERAL_RATIO(r.crLiquidation);
        }
        if (r.crOpening <= r.crLiquidation) {
            revert Errors.INVALID_LIQUIDATION_COLLATERAL_RATIO(r.crOpening, r.crLiquidation);
        }

        // validate minimumCreditBorrowToken
        if (r.minimumCreditBorrowToken == 0) {
            revert Errors.NULL_AMOUNT();
        }

        // validate min/max tenor
        if (r.minTenor == 0 || r.maxTenor == 0) {
            revert Errors.NULL_AMOUNT();
        }
        if (r.minTenor > r.maxTenor) {
            revert Errors.INVALID_TENOR_RANGE(r.minTenor, r.maxTenor);
        }
        // validate maturities (riskConfig.maturities)
        // empty allowlist is allowed by design to block limit/market orders.
        uint256 lastMaturity = 0;
        // Past/out-of-range maturity validation is performed during market orders
        // in RiskLibrary.validateMaturity to avoid DoS in UpdateConfig.
        for (uint256 i = 0; i < r.maturities.length; i++) {
            uint256 maturity = r.maturities[i];
            if (maturity <= lastMaturity) {
                revert Errors.MATURITIES_NOT_STRICTLY_INCREASING();
            }
            lastMaturity = maturity;
        }
    }

    /// @notice Validates the parameters of a single collateral asset
    /// @dev Shared by `initialize` and `addCollateralAsset`. The caller is responsible for checking that the
    ///      registry is not already full and that the asset is not already listed.
    /// @param state The state
    /// @param params The collateral asset parameters
    /// @param underlyingBorrowToken The borrow token, passed explicitly because it is not yet set during initialization
    function validateCollateralAssetParams(
        State storage state,
        InitializeCollateralAssetParams memory params,
        address underlyingBorrowToken
    ) public view {
        // validate underlying
        if (params.underlying == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        if (params.underlying == underlyingBorrowToken) {
            revert Errors.INVALID_TOKEN(params.underlying);
        }
        if (IERC20Metadata(params.underlying).decimals() > 18) {
            revert Errors.INVALID_DECIMALS(IERC20Metadata(params.underlying).decimals());
        }
        if (state.data.collateralAssetIndexPlusOne[params.underlying] != 0) {
            revert Errors.COLLATERAL_ASSET_ALREADY_LISTED(params.underlying);
        }

        // validate priceFeed
        if (params.priceFeed == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        if (IPriceFeed(params.priceFeed).decimals() != PRICE_FEED_DECIMALS) {
            revert Errors.INVALID_PRICE_FEED_DECIMALS(IPriceFeed(params.priceFeed).decimals());
        }
        if (IPriceFeed(params.priceFeed).getPrice() == 0) {
            revert Errors.NULL_AMOUNT();
        }

        // validate cap
        // N/A
    }

    /// @notice Validates the parameters for the data configuration
    /// @param state The state
    /// @param d The data configuration parameters
    function validateInitializeDataParams(State storage state, InitializeDataParams memory d) internal view {
        // validate weth
        if (d.weth == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        // validate underlyingBorrowToken
        if (d.underlyingBorrowToken == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        if (IERC20Metadata(d.underlyingBorrowToken).decimals() > 18) {
            revert Errors.INVALID_DECIMALS(IERC20Metadata(d.underlyingBorrowToken).decimals());
        }

        // validate variablePool
        if (d.variablePool == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        // validate borrowTokenVault
        if (d.borrowTokenVault == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        // validate sizeFactory
        if (d.sizeFactory == address(0)) {
            revert Errors.NULL_ADDRESS();
        }

        // validate collateralAssets
        if (d.collateralAssets.length == 0) {
            revert Errors.NULL_ARRAY();
        }
        if (d.collateralAssets.length > MAX_COLLATERAL_ASSETS) {
            revert Errors.COLLATERAL_ASSETS_LIMIT_EXCEEDED(MAX_COLLATERAL_ASSETS);
        }
        for (uint256 i = 0; i < d.collateralAssets.length; i++) {
            validateCollateralAssetParams(state, d.collateralAssets[i], d.underlyingBorrowToken);
            // the registry is empty at this point, so duplicates within the array are checked here
            for (uint256 j = 0; j < i; j++) {
                if (d.collateralAssets[j].underlying == d.collateralAssets[i].underlying) {
                    revert Errors.COLLATERAL_ASSET_ALREADY_LISTED(d.collateralAssets[i].underlying);
                }
            }
        }
    }

    /// @notice Validates the parameters for the initialization
    /// @param state The state
    /// @param owner The owner address
    /// @param f The fee configuration parameters
    /// @param r The risk configuration parameters
    /// @param d The data configuration parameters
    function validateInitialize(
        State storage state,
        address owner,
        InitializeFeeConfigParams memory f,
        InitializeRiskConfigParams memory r,
        InitializeDataParams memory d
    ) external view {
        validateOwner(owner);
        validateInitializeFeeConfigParams(f);
        validateInitializeRiskConfigParams(r);
        validateInitializeDataParams(state, d);
    }

    /// @notice Executes the initialization of the fee configuration
    /// @param state The state
    /// @param f The fee configuration parameters
    function executeInitializeFeeConfig(State storage state, InitializeFeeConfigParams memory f) internal {
        state.feeConfig.swapFeeAPR = f.swapFeeAPR;
        state.feeConfig.fragmentationFee = f.fragmentationFee;

        state.feeConfig.liquidationRewardPercent = f.liquidationRewardPercent;
        state.feeConfig.overdueCollateralProtocolPercent = f.overdueCollateralProtocolPercent;
        state.feeConfig.collateralProtocolPercent = f.collateralProtocolPercent;

        state.feeConfig.feeRecipient = f.feeRecipient;
    }

    /// @notice Executes the initialization of the risk configuration
    /// @param state The state
    /// @param r The risk configuration parameters
    function executeInitializeRiskConfig(State storage state, InitializeRiskConfigParams memory r) internal {
        state.riskConfig.crOpening = r.crOpening;
        state.riskConfig.crLiquidation = r.crLiquidation;

        state.riskConfig.minimumCreditBorrowToken = r.minimumCreditBorrowToken;

        state.riskConfig.minTenor = r.minTenor;
        state.riskConfig.maxTenor = r.maxTenor;
        for (uint256 i = 0; i < r.maturities.length; i++) {
            // slither-disable-next-line unused-return
            state.riskConfig.maturities.add(r.maturities[i]);
        }
    }

    /// @notice Deploys the deposit receipt for a collateral asset and appends it to the registry
    /// @param state The state
    /// @param params The collateral asset parameters
    function executeAddCollateralAsset(State storage state, InitializeCollateralAssetParams memory params) public {
        IERC20Metadata underlying = IERC20Metadata(params.underlying);
        NonTransferrableToken token = new NonTransferrableToken(
            address(this),
            string.concat("Rheo ", underlying.name()),
            string.concat("sz", underlying.symbol()),
            underlying.decimals()
        );

        state.data.collateralAssets
            .push(
                CollateralAsset({
                    underlying: underlying,
                    token: token,
                    priceFeed: IPriceFeed(params.priceFeed),
                    cap: params.cap,
                    depositPaused: false
                })
            );
        state.data.collateralAssetIndexPlusOne[params.underlying] = state.data.collateralAssets.length;

        emit Events.CollateralAssetAdded(params.underlying, address(token), params.priceFeed, params.cap);
    }

    /// @notice Executes the initialization of the data configuration
    /// @param state The state
    /// @param d The data configuration parameters
    function executeInitializeData(State storage state, InitializeDataParams memory d) internal {
        state.data.nextDebtPositionId = DEBT_POSITION_ID_START;
        state.data.nextCreditPositionId = CREDIT_POSITION_ID_START;

        state.data.weth = IWETH(d.weth);
        state.data.underlyingBorrowToken = IERC20Metadata(d.underlyingBorrowToken);
        state.data.variablePool = IPool(d.variablePool);

        for (uint256 i = 0; i < d.collateralAssets.length; i++) {
            executeAddCollateralAsset(state, d.collateralAssets[i]);
        }

        // legacy mirrors of the first collateral asset, kept for view/tooling compatibility
        state.data.underlyingCollateralToken = state.data.collateralAssets[0].underlying;
        state.data.collateralToken = state.data.collateralAssets[0].token;
        state.oracle.priceFeed = state.data.collateralAssets[0].priceFeed;

        state.data.debtToken = new NonTransferrableToken(
            address(this),
            string.concat("Rheo Debt ", IERC20Metadata(state.data.underlyingBorrowToken).name()),
            string.concat("szDebt", IERC20Metadata(state.data.underlyingBorrowToken).symbol()),
            IERC20Metadata(state.data.underlyingBorrowToken).decimals()
        );
        state.data.sizeFactory = ISizeFactory(d.sizeFactory);
        state.data.borrowTokenVault = NonTransferrableRebasingTokenVault(d.borrowTokenVault);
        state.data.debtTokenCap = type(uint256).max;
        state.data.overdueLiquidationRewardPercent = state.feeConfig.liquidationRewardPercent;
    }

    /// @notice Executes the initialization of the protocol
    /// @param state The state
    /// @param f The fee configuration parameters
    /// @param r The risk configuration parameters
    /// @param d The data configuration parameters
    function executeInitialize(
        State storage state,
        InitializeFeeConfigParams memory f,
        InitializeRiskConfigParams memory r,
        InitializeDataParams memory d
    ) external {
        emit Events.Initialize(msg.sender);

        executeInitializeFeeConfig(state, f);
        executeInitializeRiskConfig(state, r);
        executeInitializeData(state, d);
    }
}
