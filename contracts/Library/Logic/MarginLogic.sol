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
import {IKSwapRouter} from '../../Interface/IKSwapRouter.sol';
import {DataTypes} from '../Type/DataTypes.sol';
import {GenericLogic} from './GenericLogic.sol';
import {ValidationLogic} from './ValidationLogic.sol';
import {ReserveLogic} from './ReserveLogic.sol';

library MarginLogic {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;

  // See ILendingPool.sol for event description
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  event OpenPosition(
    address trader,
    address collateralTokenAddress,
    address shortTokenAddress,
    uint256 collateralAmount,
    uint256 shortAmount,
    uint256 liquidationThreshold,
    uint id
  );
  event ClosePosition(
    uint256 id,
    address traderAddress,
    address collateralTokenAddress,
    uint256 collateralAmount,
    address shortTokenAddress,
    uint256 shortAmount
  );

  struct OpenPositionCallVars {
    address collateralAsset;
    address shortAsset;
    address longAsset;
    uint256 collateralAmount;
    uint256 leverage;
    uint256 minLongAmountOut;
    address onBehalfOf;
    address vaultAddress;
    uint256 maximumLeverage;
    uint256 positionLiquidationThreshold;
    uint256 positionsCount;
    address swapRouterAddress;
    address oracleAddress;
  }

  struct ClosePositionCallVars {
    uint id;
    address to;
    address vaultAddress;
    uint256 minLongToShortAmountOut;
    uint256 minShortToCollateralAmountOut;
    uint256 minCollateralToShortAmountOut;
    address swapRouterAddress;
    address oracleAddress;
  }

  function openPosition(
    OpenPositionCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves
  )
    external
    returns (
      DataTypes.TraderPosition memory position
    )
  {
    require(callVars.shortAsset != callVars.longAsset, Errors.GetError(Errors.Error.LP_POSITION_INVALID));
    require((callVars.leverage < callVars.maximumLeverage) && (callVars.leverage >= WadRayMath.ray()), Errors.GetError(Errors.Error.LP_LEVERAGE_INVALID));

    DataTypes.ReserveData storage shortReserve = _reserves[callVars.shortAsset];

    uint256 supplyTokenAmount = callVars.collateralAmount.rayMul(callVars.leverage);
    uint256 amountToShort = GenericLogic.calculateAmountToShort(callVars.collateralAsset, callVars.shortAsset, supplyTokenAmount, _reserves, callVars.oracleAddress);

    ValidationLogic.validateOpenPosition(_reserves[callVars.collateralAsset], shortReserve, _reserves[callVars.longAsset], callVars.collateralAmount, amountToShort);

    IERC20(callVars.collateralAsset).safeTransferFrom(msg.sender, callVars.vaultAddress, callVars.collateralAmount);
    
    shortReserve.updateState();
    IDToken(shortReserve.dTokenAddress).mint(
        callVars.vaultAddress,
        callVars.vaultAddress,
        amountToShort,
        shortReserve.borrowIndex
      );

    shortReserve.updateInterestRates(
      callVars.shortAsset,
      shortReserve.kTokenAddress,
      0,
      amountToShort
    );

    // if this fails, means there is not enough balance
    IKToken(shortReserve.kTokenAddress).transferUnderlyingTo(callVars.vaultAddress, amountToShort);

    // transfer short into long through dex
    // TODO: validate after swap
    // TODO: add slippage to swap
    uint256 longAmount;
    {
      IKSwapRouter swapRouter = IKSwapRouter(callVars.swapRouterAddress);
      IERC20(callVars.shortAsset).safeTransfer(callVars.swapRouterAddress, amountToShort);
      (, longAmount) = swapRouter.SwapExactTokensForTokens(
        callVars.shortAsset,
        callVars.longAsset,
        amountToShort,
        callVars.minLongAmountOut,
        callVars.vaultAddress
      );
    }

    position = DataTypes.TraderPosition({
      traderAddress: callVars.onBehalfOf,
      collateralTokenAddress: callVars.collateralAsset,
      shortTokenAddress: callVars.shortAsset,
      longTokenAddress: callVars.longAsset,
      collateralAmount: callVars.collateralAmount,
      shortAmount: amountToShort,
      longAmount: longAmount,
      liquidationThreshold: callVars.positionLiquidationThreshold,
      id: callVars.positionsCount,
      isOpen: true
    });

    emit OpenPosition(
      msg.sender,
      callVars.collateralAsset,
      callVars.shortAsset,
      callVars.collateralAmount,
      amountToShort,
      callVars.positionLiquidationThreshold,
      callVars.positionsCount
    );
  }

  function closePosition(
    ClosePositionCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
    mapping(uint256 => DataTypes.TraderPosition) storage _positionsList
  ) external returns (
      uint256 paymentAmount,
      int256 pnl
    )
  {
    DataTypes.TraderPosition storage position = _positionsList[callVars.id];
    ValidationLogic.validateClosePosition(msg.sender, position);
    pnl = GenericLogic.getPnL(position, _reserves, callVars.oracleAddress);

    // swap the longAsset into shortAsset first, compensate using collateral if there are losses
    {
      uint256 returnShortAmount;
      IKSwapRouter swapRouter = IKSwapRouter(callVars.swapRouterAddress);
      {
        IERC20(position.longTokenAddress).safeTransfer(callVars.swapRouterAddress, position.longAmount);
        (, returnShortAmount) = swapRouter.SwapExactTokensForTokens(
          position.longTokenAddress,
          position.shortTokenAddress,
          position.longAmount,
          callVars.minLongToShortAmountOut,
          address(this)
        );
      }

      if (position.shortAmount <= returnShortAmount) {
        paymentAmount = 0;

        if (position.shortAmount < returnShortAmount) {
          IERC20(position.longTokenAddress)
            .safeTransfer(address(swapRouter), returnShortAmount.sub(position.shortAmount));
          (, paymentAmount) = swapRouter.SwapExactTokensForTokens(
            position.shortTokenAddress,
            position.collateralTokenAddress,
            returnShortAmount.sub(position.shortAmount),
            callVars.minShortToCollateralAmountOut,
            address(this)
          );
        }
        paymentAmount.add(position.collateralAmount);
      } else {
        uint256 collateralSpent = 0;
        if (position.shortAmount != returnShortAmount) {
          IERC20(position.longTokenAddress)
            .safeTransfer(address(swapRouter), position.shortAmount.sub(returnShortAmount));
          (, collateralSpent) = swapRouter.SwapExactTokensForTokens(
            position.collateralTokenAddress,
            position.shortTokenAddress,
            position.shortAmount.sub(returnShortAmount),
            callVars.minCollateralToShortAmountOut,
            address(this)
          );
        }
        
        paymentAmount = position.collateralAmount.sub(collateralSpent);
      }

    }
    // repay
    DataTypes.ReserveData storage shortReserve = _reserves[position.shortTokenAddress];

    uint256 paybackAmount = position.shortAmount;

    shortReserve.updateState();

    {
      IDToken(shortReserve.dTokenAddress).burn(
        callVars.vaultAddress,
        paybackAmount,
        shortReserve.borrowIndex
      );
    }
    {
      address kToken = shortReserve.kTokenAddress;
      shortReserve.updateInterestRates(position.shortTokenAddress, kToken, paybackAmount, 0);

      uint256 variableDebt = IERC20(position.shortTokenAddress).balanceOf(callVars.vaultAddress);
      if (variableDebt.sub(paybackAmount) == 0) {
        _usersConfig[callVars.vaultAddress].isBorrowing[shortReserve.id] = false;
      }

      IERC20(position.shortTokenAddress).safeTransfer(kToken, paybackAmount);

      IKToken(kToken).handleRepayment(callVars.vaultAddress, paybackAmount);
    }
    {
      _positionsList[position.id].isOpen = false;
      IERC20(position.collateralTokenAddress).safeTransfer(callVars.to, paymentAmount);
    }
    emit ClosePosition(
      position.id,
      position.traderAddress,
      position.collateralTokenAddress,
      position.collateralAmount,
      position.shortTokenAddress,
      position.shortAmount
    );
  }
}