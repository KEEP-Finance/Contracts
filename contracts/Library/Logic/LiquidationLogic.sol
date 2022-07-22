// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {MathUtils} from '../Math/MathUtils.sol';
import {WadRayMath} from '../Math/WadRayMath.sol';
import {PercentageMath} from '../Math/PercentageMath.sol';
import {IDToken} from '../../Interface/IDToken.sol';
import {IKToken} from '../../Interface/IKToken.sol';
import {ILendingPool} from '../../Interface/ILendingPool.sol';
import {IPriceOracleGetter} from '../../Interface/IPriceOracleGetter.sol';
import {Errors} from '../Helper/Errors.sol';
import {IERC20} from '../../Dependency/openzeppelin/IERC20.sol';
import {Address} from '../../Dependency/openzeppelin/Address.sol';
import {SafeMath} from '../../Dependency/openzeppelin/SafeMath.sol';
import {SafeERC20} from '../../Dependency/openzeppelin/SafeERC20.sol';
import {DataTypes} from '../Type/DataTypes.sol';
import {GenericLogic} from './GenericLogic.sol';
import {ValidationLogic} from './ValidationLogic.sol';
import {ReserveLogic} from './ReserveLogic.sol';

library LiquidationLogic {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;

  uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

  /**
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param user The address of the borrower getting liquidated
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
   * to receive the underlying collateral asset directly
   */
  struct LiquidationCallCallVars {
    address collateralAsset;
    address debtAsset;
    address user;
    uint256 debtToCover;
    bool    receiveAToken;
    uint256 reservesCount;
    address oracleAddress;
  }

  struct LiquidationCallLocalVars {
    uint256 userCollateralBalance;
    uint256 userVariableDebt;
    uint256 maxLiquidatableDebt;
    uint256 actualDebtToLiquidate;
    uint256 liquidationRatio;
    uint256 maxAmountCollateralToLiquidate;
    uint256 maxCollateralToLiquidate;
    uint256 debtAmountNeeded;
    uint256 healthFactor;
    uint256 liquidatorPreviousATokenBalance;
    IKToken collateralKtoken;
    bool isCollateralEnabled;
    DataTypes.InterestRateMode borrowRateMode;
    Errors.Error errorCode;
    Errors.Error errorMsg;
  }

  // See ILendingPool.sol for event description
  event LiquidationCall(
    address indexed collateral,
    address indexed principal,
    address indexed user,
    uint256 debtToCover,
    uint256 liquidatedCollateralAmount,
    address liquidator,
    bool receiveAToken
  );
  event LiquidationCallPosition(
    uint256 id,
    address liquidator,
    address traderAddress,
    address collateralTokenAddress,
    uint256 collateralAmount,
    address shortTokenAddress,
    uint256 shortAmount
  );
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

  /**
   * @dev Function to liquidate a position if its Health Factor drops below 1
   * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
   *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
   **/
  function liquidationCall(
    LiquidationCallCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
    mapping(uint256 => address) storage _reservesList
  ) external returns (Errors.Error, Errors.Error) {
    require(callVars.user != address(this), Errors.GetError(Errors.Error.LP_LIQUIDATE_LP));
    LiquidationCallLocalVars memory vars;
    {
    DataTypes.ReserveData storage collateralReserve = _reserves[callVars.collateralAsset];
    DataTypes.ReserveData storage debtReserve = _reserves[callVars.debtAsset];
    DataTypes.UserConfigurationMap storage userConfig = _usersConfig[callVars.user];
    {
      (, , , , vars.healthFactor) = GenericLogic.calculateUserAccountData(
        callVars.user,
        _reserves,
        userConfig,
        _reservesList,
        callVars.reservesCount,
        callVars.oracleAddress
      );

      vars.userVariableDebt = IERC20(debtReserve.dTokenAddress).balanceOf(callVars.user);

      (vars.errorCode, vars.errorMsg) = ValidationLogic.validateLiquidationCall(
        collateralReserve,
        debtReserve,
        userConfig,
        vars.healthFactor,
        vars.userVariableDebt
      );
    }
    if (vars.errorCode != Errors.Error.CM_NO_ERROR) {
      return (vars.errorCode, vars.errorMsg);
    }

    {
      vars.collateralKtoken = IKToken(collateralReserve.kTokenAddress);

      vars.userCollateralBalance = vars.collateralKtoken.balanceOf(callVars.user);

      vars.maxLiquidatableDebt = vars.userVariableDebt.percentMul(
        LIQUIDATION_CLOSE_FACTOR_PERCENT
      );

      vars.actualDebtToLiquidate = callVars.debtToCover > vars.maxLiquidatableDebt
        ? vars.maxLiquidatableDebt
        : callVars.debtToCover;
    }

    {
      (
        vars.maxCollateralToLiquidate,
        vars.debtAmountNeeded
      ) = _calculateAvailableCollateralToLiquidate(
        AvailableCollateralToLiquidateCallVars({
          collateralAsset: callVars.collateralAsset,
          debtAsset: callVars.debtAsset,
          debtToCover: vars.actualDebtToLiquidate,
          userCollateralBalance: vars.userCollateralBalance,
          oracleAddress: callVars.oracleAddress
        }),
        collateralReserve,
        debtReserve
      );
    }

    // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
    // collateral to cover the actual amount that is being liquidated, hence we liquidate
    // a smaller amount
    {
      if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
        vars.actualDebtToLiquidate = vars.debtAmountNeeded;
      }
    }

    // If the liquidator reclaims the underlying asset, we make sure there is enough available liquidity in the
    // collateral reserve
    {
      if (!callVars.receiveAToken) {
        uint256 currentAvailableCollateral =
          IERC20(callVars.collateralAsset).balanceOf(address(vars.collateralKtoken));
        if (currentAvailableCollateral < vars.maxCollateralToLiquidate) {
          return (
            Errors.Error.CM_NOT_ENOUGH_LIQUIDITY,
            Errors.Error.LL_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE
          );
        }
      }
    }

    {
      debtReserve.updateState();

      IDToken(debtReserve.dTokenAddress).burn(
        callVars.user,
        vars.actualDebtToLiquidate,
        debtReserve.borrowIndex
      );

      debtReserve.updateInterestRates(
        callVars.debtAsset,
        debtReserve.kTokenAddress,
        vars.actualDebtToLiquidate,
        0
      );
    }

    {
      if (callVars.receiveAToken) {
        vars.liquidatorPreviousATokenBalance = IERC20(vars.collateralKtoken).balanceOf(msg.sender);
        vars.collateralKtoken.transferOnLiquidation(callVars.user, msg.sender, vars.maxCollateralToLiquidate);
  
        if (vars.liquidatorPreviousATokenBalance == 0) {
          DataTypes.UserConfigurationMap storage liquidatorConfig = _usersConfig[msg.sender];
          liquidatorConfig.isUsingAsCollateral[collateralReserve.id] = true;
          emit ReserveUsedAsCollateralEnabled(callVars.collateralAsset, msg.sender);
        }
      } else {
        collateralReserve.updateState();
        collateralReserve.updateInterestRates(
          callVars.collateralAsset,
          address(vars.collateralKtoken),
          0,
          vars.maxCollateralToLiquidate
        );

        // Burn the equivalent amount of aToken, sending the underlying to the liquidator
        vars.collateralKtoken.burn(
          callVars.user,
          msg.sender,
          vars.maxCollateralToLiquidate,
          collateralReserve.liquidityIndex
        );
      }
    }

    // If the collateral being liquidated is equal to the user balance,
    // we set the currency as not being used as collateral anymore
    {
      if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
        userConfig.isUsingAsCollateral[collateralReserve.id] = false;
        emit ReserveUsedAsCollateralDisabled(callVars.collateralAsset, callVars.user);
      }
    }

    // Transfers the debt asset being repaid to the aToken, where the liquidity is kept
    {
      IERC20(callVars.debtAsset).safeTransferFrom(
        msg.sender,
        address(this),
        vars.actualDebtToLiquidate
      );
      IERC20(callVars.debtAsset).safeTransfer(
        debtReserve.kTokenAddress,
        vars.actualDebtToLiquidate
      );
    }
    }
    {
      emit LiquidationCall(
        callVars.collateralAsset,
        callVars.debtAsset,
        callVars.user,
        vars.actualDebtToLiquidate,
        vars.maxCollateralToLiquidate,
        msg.sender,
        callVars.receiveAToken
      );
    }

    return (Errors.Error.CM_NO_ERROR, Errors.Error.LL_NO_ERRORS);
  }

  struct LiquidationCallPositionCallVars {
    uint id;
    address oracleAddress;
  }

  function liquidationCallPosition(
    LiquidationCallPositionCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
    mapping(uint256 => DataTypes.TraderPosition) storage _positionsList
  ) external {
    DataTypes.TraderPosition storage position = _positionsList[callVars.id];
    ValidationLogic.validateLiquidationCallPosition(
        position,
        _reserves,
        callVars.oracleAddress
      );

    // repay
    DataTypes.ReserveData storage shortReserve = _reserves[position.shortTokenAddress];

    shortReserve.updateState();
    IDToken(shortReserve.dTokenAddress).burn(
      address(this),
      position.shortAmount,
      shortReserve.borrowIndex
    );

    shortReserve.updateInterestRates(position.shortTokenAddress, shortReserve.kTokenAddress, position.shortAmount, 0);

    uint256 variableDebt = IERC20(position.shortTokenAddress).balanceOf(address(this));
    if (variableDebt.sub(position.shortAmount) == 0) {
      _usersConfig[address(this)].isBorrowing[shortReserve.id] = false;
    }

    IERC20(position.shortTokenAddress).safeTransferFrom(
      msg.sender,
      shortReserve.kTokenAddress,
      position.shortAmount
    );
    IKToken(shortReserve.kTokenAddress).handleRepayment(address(this), position.shortAmount);

    _positionsList[position.id].isOpen = false;
    IERC20(position.longTokenAddress).safeTransfer(msg.sender, position.longAmount);
    IERC20(position.collateralTokenAddress).safeTransfer(msg.sender, position.collateralAmount);

    emit LiquidationCallPosition(
      callVars.id,
      msg.sender,
      position.traderAddress,
      position.collateralTokenAddress,
      position.collateralAmount,
      position.shortTokenAddress,
      position.shortAmount
    );
  }

  /**
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
   */
  struct AvailableCollateralToLiquidateCallVars {
    address collateralAsset;
    address debtAsset;
    uint256 debtToCover;
    uint256 userCollateralBalance;
    address oracleAddress;
  }

  struct AvailableCollateralToLiquidateLocalVars {
    uint256 userCompoundedBorrowBalance;
    uint256 liquidationBonus;
    uint256 collateralPrice;
    uint256 debtAssetPrice;
    uint256 maxAmountCollateralToLiquidate;
    uint256 debtAssetDecimals;
    uint256 collateralDecimals;
  }

  /**
   * @dev Calculates how much of a specific collateral can be liquidated, given
   * a certain amount of debt asset.
   * - This function needs to be called after all the checks to validate the liquidation have been performed,
   *   otherwise it might fail.
   * @param collateralReserve The data of the collateral reserve
   * @param debtReserve The data of the debt reserve
   * @param callVars The other variables
   * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints
   *                           (user balance, close factor)
   * @return debtAmountNeeded: The amount to repay with the liquidation
   **/
  function _calculateAvailableCollateralToLiquidate(
    AvailableCollateralToLiquidateCallVars memory callVars,
    DataTypes.ReserveData storage collateralReserve,
    DataTypes.ReserveData storage debtReserve
  ) internal view returns (uint256, uint256) {
    uint256 collateralAmount = 0;
    uint256 debtAmountNeeded = 0;
    IPriceOracleGetter oracle = IPriceOracleGetter(callVars.oracleAddress);

    AvailableCollateralToLiquidateLocalVars memory vars;

    vars.collateralPrice = oracle.getAssetPrice(callVars.collateralAsset);
    vars.debtAssetPrice = oracle.getAssetPrice(callVars.debtAsset);

    vars.liquidationBonus = collateralReserve.configuration.liquidationBonus;
    vars.collateralDecimals = collateralReserve.configuration.decimals;
    vars.debtAssetDecimals = debtReserve.configuration.decimals;

    // This is the maximum possible amount of the selected collateral that can be liquidated, given the
    // max amount of liquidatable debt
    vars.maxAmountCollateralToLiquidate = vars
      .debtAssetPrice
      .mul(callVars.debtToCover)
      .mul(10**vars.collateralDecimals)
      .percentMul(vars.liquidationBonus)
      .div(vars.collateralPrice.mul(10**vars.debtAssetDecimals));

    if (vars.maxAmountCollateralToLiquidate > callVars.userCollateralBalance) {
      collateralAmount = callVars.userCollateralBalance;
      debtAmountNeeded = vars
        .collateralPrice
        .mul(collateralAmount)
        .mul(10**vars.debtAssetDecimals)
        .div(vars.debtAssetPrice.mul(10**vars.collateralDecimals))
        .percentDiv(vars.liquidationBonus);
    } else {
      collateralAmount = vars.maxAmountCollateralToLiquidate;
      debtAmountNeeded = callVars.debtToCover;
    }
    return (collateralAmount, debtAmountNeeded);
  }
}