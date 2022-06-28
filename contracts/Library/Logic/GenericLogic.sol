// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IERC20} from '../../Dependency/openzeppelin/IERC20.sol';
import {SafeMath} from '../../Dependency/openzeppelin/SafeMath.sol';
import {SafeERC20} from '../../Dependency/openzeppelin/SafeERC20.sol';
import {ReserveLogic} from './ReserveLogic.sol';
import {WadRayMath} from '../Math/WadRayMath.sol';
import {PercentageMath} from '../Math/PercentageMath.sol';
import {IPriceOracleGetter} from '../../Interface/IPriceOracleGetter.sol';
import {IAggregationRouterV4} from '../../Interface/1inch/IAggregationRouterV4.sol';
import {DataTypes} from '../Type/DataTypes.sol';

library GenericLogic {
  using ReserveLogic for DataTypes.ReserveData;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether; // 1e18

  struct balanceDecreaseAllowedLocalVars {
    uint256 decimals;
    uint256 liquidationThreshold;
    uint256 totalCollateralInETH;
    uint256 totalDebtInETH;
    uint256 avgLiquidationThreshold;
    uint256 amountToDecreaseInETH;
    uint256 collateralBalanceAfterDecrease;
    uint256 liquidationThresholdAfterDecrease;
    uint256 healthFactorAfterDecrease;
    bool reserveUsageAsCollateralEnabled;
  }

  function swapToTargetAsset(
    
  ) external returns (
    uint256 heldAmount
  ) {

  }

  function calculateAmountToBorrow(
    address supplyTokenAddress,
    address borrowTokenAddress,
    uint256 supplyTokenAmount,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    address oracle
  ) external view returns (
    uint256 amountToBorrow
  ) {
    uint256 supplyUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(supplyTokenAddress);
    uint8 supplyDecimals = reservesData[supplyTokenAddress].configuration.decimals;
    uint256 borrowUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(borrowTokenAddress);
    uint8 borrowDecimals = reservesData[borrowTokenAddress].configuration.decimals;

    amountToBorrow = supplyTokenAmount.mul(supplyUnitPrice).mul(10**borrowDecimals);
    amountToBorrow = amountToBorrow.div(borrowUnitPrice).div(10**supplyDecimals);
  }

  function getPnL(
    DataTypes.TraderPosition storage position,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    address oracle
  )
  external
  view
  returns (int256 pnl)
  {
    uint256 borrowUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(position.borrowedTokenAddress);
    uint8 borrowDecimals = reservesData[position.borrowedTokenAddress].configuration.decimals;
    uint256 borrowValue = borrowUnitPrice.mul(position.borrowedAmount).div(10**borrowDecimals);

    uint256 heldUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(position.heldTokenAddress);
    uint8 heldDecimals = reservesData[position.heldTokenAddress].configuration.decimals;
    uint256 heldValue = heldUnitPrice.mul(position.heldAmount).div(10**heldDecimals);
    
    pnl = int256(heldValue) - int256(borrowValue);
  }

  // returns health factor in wad
  function calculatePositionHealthFactor(
    DataTypes.TraderPosition storage position,
    uint256 positionLiquidationThreshold,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    address oracle
  )
  external
  view
  returns (uint256 healthFactor)
  {
    uint256 borrowValue;
    uint256 heldValue;
    uint256 marginValue;

    {
      uint256 borrowUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(position.borrowedTokenAddress);
      uint8 borrowDecimals = reservesData[position.borrowedTokenAddress].configuration.decimals;
      borrowValue = borrowUnitPrice.mul(position.borrowedAmount).div(10**borrowDecimals);
    }
    {    
      uint256 heldUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(position.heldTokenAddress);
      uint8 heldDecimals = reservesData[position.heldTokenAddress].configuration.decimals;
      heldValue = heldUnitPrice.mul(position.heldAmount).div(10**heldDecimals);
    }
    {
      uint256 marginUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(position.marginTokenAddress);
      uint8 marginDecimals = reservesData[position.marginTokenAddress].configuration.decimals;
      marginValue = marginUnitPrice.mul(position.marginAmount).div(10**marginDecimals);
    }
    healthFactor = marginValue.add(heldValue).sub(borrowValue);
    healthFactor = healthFactor.wadDiv(marginValue.rayMul(positionLiquidationThreshold));
  }

  /**
   * @dev Checks if a specific balance decrease is allowed
   * (i.e. doesn't bring the user borrow position health factor under HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
   * @param asset The address of the underlying asset of the reserve
   * @param user The address of the user
   * @param amount The amount to decrease
   * @param reservesData The data of all the reserves
   * @param userConfig The user configuration
   * @param reserves The list of all the active reserves
   * @param oracle The address of the oracle contract
   * @return true if the decrease of the balance is allowed
   **/
  function balanceDecreaseAllowed(
    address asset,
    address user,
    uint256 amount,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    DataTypes.UserConfigurationMap storage userConfig,
    mapping(uint256 => address) storage reserves,
    uint256 reservesCount,
    address oracle
  ) external view returns (bool) {
    {
      bool isBorrowingAny = false;
      for (uint i = 0; i < reservesCount; i++) {
        if (userConfig.isBorrowing[i] == true) {
          isBorrowingAny = true;
          break;
        }
      }
      if (!isBorrowingAny || !userConfig.isUsingAsCollateral[reservesData[asset].id]) {
        return true;
      }
    }

    balanceDecreaseAllowedLocalVars memory vars;

    vars.liquidationThreshold = reservesData[asset].configuration.liquidationThreshold;
    vars.decimals = reservesData[asset].configuration.decimals;

    if (vars.liquidationThreshold == 0) {
      return true;
    }

    (
      vars.totalCollateralInETH,
      vars.totalDebtInETH,
      ,
      vars.avgLiquidationThreshold,

    ) = calculateUserAccountData(user, reservesData, userConfig, reserves, reservesCount, oracle);

    if (vars.totalDebtInETH == 0) {
      return true;
    }

    vars.amountToDecreaseInETH = IPriceOracleGetter(oracle).getAssetPrice(asset).mul(amount).div(
      10**vars.decimals
    );

    vars.collateralBalanceAfterDecrease = vars.totalCollateralInETH.sub(vars.amountToDecreaseInETH);

    //if there is a borrow, there can't be 0 collateral
    if (vars.collateralBalanceAfterDecrease == 0) {
      return false;
    }

    vars.liquidationThresholdAfterDecrease = vars
      .totalCollateralInETH
      .mul(vars.avgLiquidationThreshold)
      .sub(vars.amountToDecreaseInETH.mul(vars.liquidationThreshold))
      .div(vars.collateralBalanceAfterDecrease);

    uint256 healthFactorAfterDecrease =
      calculateHealthFactorFromBalances(
        vars.collateralBalanceAfterDecrease,
        vars.totalDebtInETH,
        vars.liquidationThresholdAfterDecrease
      );

    return healthFactorAfterDecrease >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
  }

  struct CalculateUserAccountDataVars {
    uint256 reserveUnitPrice;
    uint256 tokenUnit;
    uint256 compoundedLiquidityBalance;
    uint256 compoundedBorrowBalance;
    uint256 decimals;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 i;
    uint256 healthFactor;
    uint256 totalCollateralInETH;
    uint256 totalDebtInETH;
    uint256 avgLtv;
    uint256 avgLiquidationThreshold;
    uint256 reservesLength;
    bool healthFactorBelowThreshold;
    address currentReserveAddress;
    bool usageAsCollateralEnabled;
    bool userUsesReserveAsCollateral;
  }

  /**
   * @dev Calculates the user data across the reserves.
   * this includes the total liquidity/collateral/borrow balances in ETH,
   * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
   * @param user The address of the user
   * @param reservesData Data of all the reserves
   * @param userConfig The configuration of the user
   * @param reserves The list of the available reserves
   * @param oracle The price oracle address
   * @return The total collateral and total debt of the user in ETH, the avg ltv, liquidation threshold and the HF
   **/
  function calculateUserAccountData(
    address user,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    DataTypes.UserConfigurationMap storage userConfig,
    mapping(uint256 => address) storage reserves,
    uint256 reservesCount,
    address oracle
  )
    internal
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    {
      bool isEmpty = true;
      for (uint i = 0; i < reservesCount; i++) {
        if (userConfig.isUsingAsCollateral[i] == true || userConfig.isBorrowing[i] == true) {
          isEmpty = false;
          break;
        }
      }
      if (isEmpty) {
        return (0, 0, 0, 0, type(uint256).max);
      }
    }

    CalculateUserAccountDataVars memory vars;
    for (vars.i = 0; vars.i < reservesCount; vars.i++) {
      if (!(userConfig.isUsingAsCollateral[vars.i] || userConfig.isBorrowing[vars.i])) {
        continue;
      }

      vars.currentReserveAddress = reserves[vars.i];
      DataTypes.ReserveData memory currentReserve = reservesData[vars.currentReserveAddress];

      vars.ltv = currentReserve.configuration.ltv;
      vars.liquidationThreshold = currentReserve.configuration.liquidationThreshold;
      vars.decimals = currentReserve.configuration.decimals;

      vars.tokenUnit = 10**vars.decimals;
      vars.reserveUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(vars.currentReserveAddress);

      if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral[vars.i]) {
        vars.compoundedLiquidityBalance = IERC20(currentReserve.kTokenAddress).balanceOf(user);

        uint256 liquidityBalanceETH =
          vars.reserveUnitPrice.mul(vars.compoundedLiquidityBalance).div(vars.tokenUnit);

        vars.totalCollateralInETH = vars.totalCollateralInETH.add(liquidityBalanceETH);

        vars.avgLtv = vars.avgLtv.add(liquidityBalanceETH.mul(vars.ltv));
        vars.avgLiquidationThreshold = vars.avgLiquidationThreshold.add(
          liquidityBalanceETH.mul(vars.liquidationThreshold)
        );
      }

      if (userConfig.isBorrowing[vars.i]) {
        vars.compoundedBorrowBalance = 
          IERC20(currentReserve.dTokenAddress).balanceOf(user);

        vars.totalDebtInETH = vars.totalDebtInETH.add(
          vars.reserveUnitPrice.mul(vars.compoundedBorrowBalance).div(vars.tokenUnit)
        );
      }
    }

    vars.avgLtv = vars.totalCollateralInETH > 0 ? vars.avgLtv.div(vars.totalCollateralInETH) : 0;
    vars.avgLiquidationThreshold = vars.totalCollateralInETH > 0
      ? vars.avgLiquidationThreshold.div(vars.totalCollateralInETH)
      : 0;

    vars.healthFactor = calculateHealthFactorFromBalances(
      vars.totalCollateralInETH,
      vars.totalDebtInETH,
      vars.avgLiquidationThreshold
    );
    return (
      vars.totalCollateralInETH,
      vars.totalDebtInETH,
      vars.avgLtv,
      vars.avgLiquidationThreshold,
      vars.healthFactor
    );
  }

  /**
   * @dev Calculates the health factor from the corresponding balances
   * @param totalCollateralInETH The total collateral in ETH
   * @param totalDebtInETH The total debt in ETH
   * @param liquidationThreshold The avg liquidation threshold
   * @return The health factor calculated from the balances provided
   **/
  function calculateHealthFactorFromBalances(
    uint256 totalCollateralInETH,
    uint256 totalDebtInETH,
    uint256 liquidationThreshold
  ) internal pure returns (uint256) {
    if (totalDebtInETH == 0) return type(uint256).max;

    return (totalCollateralInETH.percentMul(liquidationThreshold)).wadDiv(totalDebtInETH);
  }

  /**
   * @dev Calculates the equivalent amount in ETH that an user can borrow, depending on the available collateral and the
   * average Loan To Value
   * @param totalCollateralInETH The total collateral in ETH
   * @param totalDebtInETH The total borrow balance
   * @param ltv The average loan to value
   * @return the amount available to borrow in ETH for the user
   **/

  function calculateAvailableBorrowsETH(
    uint256 totalCollateralInETH,
    uint256 totalDebtInETH,
    uint256 ltv
  ) internal pure returns (uint256) {
    uint256 availableBorrowsETH = totalCollateralInETH.percentMul(ltv);

    if (availableBorrowsETH < totalDebtInETH) {
      return 0;
    }

    availableBorrowsETH = availableBorrowsETH.sub(totalDebtInETH);
    return availableBorrowsETH;
  }
}
