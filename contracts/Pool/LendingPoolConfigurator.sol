// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../Interface/ILendingPool.sol';
import {IERC20Detailed} from '../Dependency/openzeppelin/IERC20Detailed.sol';
import {Errors} from '../Library/Helper/Errors.sol';
import {PercentageMath} from '../Library/Math/PercentageMath.sol';
import {DataTypes} from '../Library/Type/DataTypes.sol';
import {ILendingPoolConfigurator} from '../Interface/ILendingPoolConfigurator.sol';
import {KToken} from '../Token/KToken.sol';
import {DToken} from '../Token/DToken.sol';

contract LendingPoolConfigurator is ILendingPoolConfigurator {
  using PercentageMath for uint256;

  ILendingPoolAddressesProvider internal addressesProvider;
  ILendingPool internal pool;

  modifier onlyMainAdmin {
    require(addressesProvider.getMainAdmin() == msg.sender, Errors.GetError(Errors.Error.CALLER_NOT_MAIN_ADMIN));
    _;
  }

  modifier onlyEmergencyAdmin {
    require(
      addressesProvider.getEmergencyAdmin() == msg.sender,
      Errors.GetError(Errors.Error.CALLER_NOT_EMERGENCY_ADMIN)
    );
    _;
  }

  constructor(
    ILendingPoolAddressesProvider provider,
    ILendingPool lending_pool
  ) {
    addressesProvider = provider;
    pool = lending_pool;
  }

  /**
   * @dev Initializes reserves in batch
   **/
  function batchInitReserve(InitReserveInput[] calldata input) external onlyMainAdmin {
    ILendingPool cachedPool = pool;
    for (uint256 i = 0; i < input.length; i++) {
      _initReserve(cachedPool, input[i]);
    }
  }

  function initReserve(InitReserveInput calldata input) external onlyMainAdmin {
    ILendingPool cachedPool = pool;
    _initReserve(cachedPool, input);
  }

  function _initReserve(ILendingPool _pool, InitReserveInput calldata input) internal {
    KToken kToken = new KToken(
      _pool,
      input.treasury,
      input.underlyingAsset,
      input.kTokenDecimals,
      input.kTokenName,
      input.kTokenSymbol
    );
    address kTokenAddress = address(kToken);

    DToken dToken = new DToken(
      _pool,
      input.underlyingAsset,
      input.dTokenDecimals,
      input.dTokenName,
      input.dTokenSymbol
    );
    address dTokenAddress = address(dToken);

    pool.initReserve(
      input.underlyingAsset,
      kTokenAddress,
      dTokenAddress,
      input.interestRateStrategyAddress
    );

    DataTypes.ReserveConfiguration memory currentConfig =
      pool.getConfiguration(input.underlyingAsset);

    currentConfig.decimals = input.underlyingAssetDecimals;
    currentConfig.active = true;
    currentConfig.frozen = false;

    pool.setConfiguration(input.underlyingAsset, currentConfig);

    emit ReserveInitialized(
      input.underlyingAsset,
      kTokenAddress,
      dTokenAddress,
      input.interestRateStrategyAddress
    );
  }

  /**
   * @dev Enables borrowing on a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function enableBorrowingOnReserve(address asset)
    external
    onlyMainAdmin
  {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);

    currentConfig.borrowingEnabled = true;

    pool.setConfiguration(asset, currentConfig);

    emit BorrowingEnabledOnReserve(asset);
  }

  /**
   * @dev Disables borrowing on a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function disableBorrowingOnReserve(address asset) external onlyMainAdmin {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);

    currentConfig.borrowingEnabled = false;

    pool.setConfiguration(asset, currentConfig);
    emit BorrowingDisabledOnReserve(asset);
  }

  /**
   * @dev Configures the reserve collateralization parameters
   * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
   * @param asset The address of the underlying asset of the reserve
   * @param ltv The loan to value of the asset when used as collateral
   * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
   * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
   * means the liquidator will receive a 5% bonus
   **/
  function configureReserveAsCollateral(
    address asset,
    uint256 ltv,
    uint256 liquidationThreshold,
    uint256 liquidationBonus
  ) external onlyMainAdmin {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);

    //validation of the parameters: the LTV can
    //only be lower or equal than the liquidation threshold
    //(otherwise a loan against the asset would cause instantaneous liquidation)
    require(ltv <= liquidationThreshold, Errors.GetError(Errors.Error.LPC_INVALID_CONFIGURATION));

    if (liquidationThreshold != 0) {
      //liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
      //collateral than needed to cover the debt
      require(
        liquidationBonus > PercentageMath.PERCENTAGE_FACTOR,
        Errors.GetError(Errors.Error.LPC_INVALID_CONFIGURATION)
      );

      //if threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
      //a loan is taken there is enough collateral available to cover the liquidation bonus
      require(
        liquidationThreshold.percentMul(liquidationBonus) <= PercentageMath.PERCENTAGE_FACTOR,
        Errors.GetError(Errors.Error.LPC_INVALID_CONFIGURATION)
      );
    } else {
      require(liquidationBonus == 0, Errors.GetError(Errors.Error.LPC_INVALID_CONFIGURATION));
      // if the liquidation threshold is being set to 0,
      // the reserve is being disabled as collateral. To do so,
      // we need to ensure no liquidity is supplied
      _checkNoLiquidity(asset);
    }

    currentConfig.ltv = ltv;
    currentConfig.liquidationThreshold = liquidationThreshold;
    currentConfig.liquidationBonus = liquidationBonus;

    pool.setConfiguration(asset, currentConfig);

    emit CollateralConfigurationChanged(asset, ltv, liquidationThreshold, liquidationBonus);
  }

  function configureReservePosition(
    address asset,
    bool collateralEnabled,
    bool longEnabled,
    bool shortEnabled
  ) external onlyMainAdmin {
    DataTypes.ReservePositionConfiguration memory positionConfig =
      DataTypes.ReservePositionConfiguration(
        false,
        collateralEnabled,
        longEnabled,
        shortEnabled
      );
    
    pool.setPositionConfiguration(asset, positionConfig);
    emit PositionConfigurationChanged(collateralEnabled, longEnabled, shortEnabled);
  }

  /**
   * @dev Activates a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function activateReserve(address asset) external onlyMainAdmin {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);

    currentConfig.active = true;

    pool.setConfiguration(asset, currentConfig);

    emit ReserveActivated(asset);
  }

  /**
   * @dev Deactivates a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function deactivateReserve(address asset) external onlyMainAdmin {
    _checkNoLiquidity(asset);

    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);

    currentConfig.active = false;

    pool.setConfiguration(asset, currentConfig);

    emit ReserveDeactivated(asset);
  }

  /**
   * @dev Freezes a reserve. A frozen reserve doesn't allow any new supply, borrow or rate swap
   *  but allows repayments, liquidations, rate rebalances and withdrawals
   * @param asset The address of the underlying asset of the reserve
   **/
  function freezeReserve(address asset) external onlyMainAdmin {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);
    currentConfig.frozen = true;
    pool.setConfiguration(asset, currentConfig);
    emit ReserveFrozen(asset);
  }

  /**
   * @dev Unfreezes a reserve
   * @param asset The address of the underlying asset of the reserve
   **/
  function unfreezeReserve(address asset) external onlyMainAdmin {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);
    currentConfig.frozen = false;
    pool.setConfiguration(asset, currentConfig);
    emit ReserveUnfrozen(asset);
  }

  /**
   * @dev Updates the reserve factor of a reserve
   * @param asset The address of the underlying asset of the reserve
   * @param reserveFactor The new reserve factor of the reserve
   **/
  function setReserveFactor(address asset, uint256 reserveFactor) external onlyMainAdmin {
    DataTypes.ReserveConfiguration memory currentConfig = pool.getConfiguration(asset);
    currentConfig.reserveFactor = reserveFactor;
    pool.setConfiguration(asset, currentConfig);
    emit ReserveFactorChanged(asset, reserveFactor);
  }

  /**
   * @dev Sets the interest rate strategy of a reserve
   * @param asset The address of the underlying asset of the reserve
   * @param rateStrategyAddress The new address of the interest strategy contract
   **/
  function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
    external
    onlyMainAdmin
  {
    pool.setReserveInterestRateStrategyAddress(asset, rateStrategyAddress);
    emit ReserveInterestRateStrategyChanged(asset, rateStrategyAddress);
  }

  function activateReservePosition(address asset) external onlyMainAdmin {
    DataTypes.ReservePositionConfiguration memory currentPositionConfig = pool.getPositionConfiguration(asset);
    currentPositionConfig.active = true;
    pool.setPositionConfiguration(asset, currentPositionConfig);

    emit ReservePositionActivated(asset);
  }

  // Note: trader can close position, but cannot open position with the asset after is deactivated
  function deactivateReservePosition(address asset) external onlyMainAdmin {
    DataTypes.ReservePositionConfiguration memory currentPositionConfig = pool.getPositionConfiguration(asset);
    currentPositionConfig.active = false;
    pool.setPositionConfiguration(asset, currentPositionConfig);

    emit ReservePositionDeactivated(asset);
  }

  /**
   * @dev pauses or unpauses all the actions of the protocol, including aToken transfers
   * @param val true if protocol needs to be paused, false otherwise
   **/
  function setPoolPause(bool val) external onlyEmergencyAdmin {
    pool.setPause(val);
  }

  function _checkNoLiquidity(address asset) internal view {
    DataTypes.ReserveData memory reserveData = pool.getReserveData(asset);

    uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(reserveData.kTokenAddress);

    require(
      availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
      Errors.GetError(Errors.Error.LPC_RESERVE_LIQUIDITY_NOT_0)
    );
  }
}
