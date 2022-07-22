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

library MarketLogic {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;
  
  // See ILendingPool.sol for event description
  event Supply(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount
  );
  event Withdraw(
    address indexed reserve,
    address indexed user,
    address indexed to,
    uint256 amount
  );
  event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint256 borrowRateMode,
    uint256 borrowRate
  );
  event Repay(
    address indexed reserve,
    address indexed user,
    address indexed repayer,
    uint256 amount
  );
  event FlashLoan(
    address indexed target,
    address indexed initiator,
    address indexed asset,
    uint256 amount,
    uint256 premium,
    uint16 referralCode
  );
  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  struct SupplyCallVars {
    address asset;
    uint256 amount;
    address onBehalfOf;
  }

  function supply(
    SupplyCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
  ) external {
    DataTypes.ReserveData storage reserve = _reserves[callVars.asset];

    ValidationLogic.validateSupply(reserve, callVars.amount);

    address kToken = reserve.kTokenAddress;

    reserve.updateState();
    reserve.updateInterestRates(callVars.asset, kToken, callVars.amount, 0);

    // Need to approve to kToken first
    IERC20(callVars.asset).safeTransferFrom(msg.sender, kToken, callVars.amount);

    bool isFirstSupply = IKToken(kToken).mint(callVars.onBehalfOf, callVars.amount, reserve.liquidityIndex);

    if (isFirstSupply) {
      _usersConfig[callVars.onBehalfOf].isUsingAsCollateral[reserve.id] = true;
      emit ReserveUsedAsCollateralEnabled(callVars.asset, callVars.onBehalfOf);
    }

    emit Supply(callVars.asset, msg.sender, callVars.onBehalfOf, callVars.amount);
  }

  struct WithdrawCallVars {
    address asset;
    uint256 amount;
    address to;
    uint256 reservesCount;
    address oracleAddress;
  }

  struct WithdrawLocalVars {
    address kToken;
    uint256 userBalance;
    uint256 amountToWithdraw;
  }

  function withdraw(
    WithdrawCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
    mapping(uint256 => address) storage _reservesList
  ) external returns (uint256) {
    DataTypes.ReserveData storage reserve = _reserves[callVars.asset];
    WithdrawLocalVars memory vars;

    vars.kToken = reserve.kTokenAddress;

    vars.userBalance = IKToken(vars.kToken).balanceOf(msg.sender);

    vars.amountToWithdraw = callVars.amount;

    if (callVars.amount == type(uint256).max) {
      vars.amountToWithdraw = vars.userBalance;
    }

    ValidationLogic.validateWithdraw(
      callVars.asset,
      vars.amountToWithdraw,
      vars.userBalance,
      _reserves,
      _usersConfig[msg.sender],
      _reservesList,
      callVars.reservesCount,
      callVars.oracleAddress
    );

    reserve.updateState();

    reserve.updateInterestRates(callVars.asset, vars.kToken, 0, vars.amountToWithdraw);

    if (vars.amountToWithdraw == vars.userBalance) {
      _usersConfig[msg.sender].isUsingAsCollateral[reserve.id] = false;
      emit ReserveUsedAsCollateralDisabled(callVars.asset, msg.sender);
    }

    // transfer asset operation is in this burn function
    IKToken(vars.kToken).burn(msg.sender, callVars.to, vars.amountToWithdraw, reserve.liquidityIndex);

    emit Withdraw(callVars.asset, msg.sender, callVars.to, vars.amountToWithdraw);

    return vars.amountToWithdraw;
  }

  struct BorrowCallVars {
    address asset;
    address user;
    address onBehalfOf;
    uint256 amount;
    uint256 interestRateMode;
    bool releaseUnderlying;
    address oracleAddress;
    uint256 reservesCount;
  }

  function borrow(
    BorrowCallVars memory callVars,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig,
    mapping(uint256 => address) storage _reservesList
  ) external {
    DataTypes.ReserveData storage reserve = _reserves[callVars.asset];
    DataTypes.UserConfigurationMap storage userConfig = _usersConfig[callVars.onBehalfOf];

    uint256 amountInETH =
      IPriceOracleGetter(callVars.oracleAddress).getAssetPrice(callVars.asset).mul(callVars.amount).div(
        10**reserve.configuration.decimals
      );

    ValidationLogic.validateBorrow(
      ValidationLogic.ValidateBorrowCallVars({
        asset: callVars.asset,
        userAddress: callVars.onBehalfOf,
        amount: callVars.amount,
        amountInETH: amountInETH,
        interestRateMode: callVars.interestRateMode,
        reservesCount: callVars.reservesCount,
        oracleAddress: callVars.oracleAddress
      }),
      reserve,
      _reserves,
      userConfig,
      _reservesList
    );

    reserve.updateState();

    bool isFirstBorrowing = false;
    {
      isFirstBorrowing = IDToken(reserve.dTokenAddress).mint(
        callVars.user,
        callVars.onBehalfOf,
        callVars.amount,
        reserve.borrowIndex
      );
    }

    if (isFirstBorrowing) {
      userConfig.isBorrowing[reserve.id] = true;
    }

    address kToken = reserve.kTokenAddress;

    reserve.updateInterestRates(
      callVars.asset,
      kToken,
      0,
      callVars.releaseUnderlying ? callVars.amount : 0
    );

    if (callVars.releaseUnderlying) {
      IKToken(kToken).transferUnderlyingTo(callVars.user, callVars.amount);
    }

    emit Borrow(
      callVars.asset,
      msg.sender,
      callVars.onBehalfOf,
      callVars.amount,
      callVars.interestRateMode,
      reserve.currentBorrowRate
    );
  }

  function repay(
    address asset,
    uint256 amount,
    uint256 rateMode,
    address onBehalfOf,
    mapping(address => DataTypes.ReserveData) storage _reserves,
    mapping(address => DataTypes.UserConfigurationMap) storage _usersConfig
  ) external returns (uint256) {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    uint256 variableDebt = IERC20(reserve.dTokenAddress).balanceOf(onBehalfOf);

    DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode(rateMode);

    ValidationLogic.validateRepay(
      reserve,
      amount,
      interestRateMode,
      onBehalfOf,
      variableDebt
    );

    uint256 paybackAmount = variableDebt;

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }

    reserve.updateState();

    {
      IDToken(reserve.dTokenAddress).burn(
        onBehalfOf,
        paybackAmount,
        reserve.borrowIndex
      );
    }

    address kToken = reserve.kTokenAddress;
    reserve.updateInterestRates(asset, kToken, paybackAmount, 0);

    if (variableDebt.sub(paybackAmount) == 0) {
      _usersConfig[onBehalfOf].isBorrowing[reserve.id] = false;
    }

    IERC20(asset).safeTransferFrom(msg.sender, address(this), paybackAmount);
    IERC20(asset).safeTransfer(kToken, paybackAmount);

    IKToken(kToken).handleRepayment(msg.sender, paybackAmount);

    emit Repay(asset, onBehalfOf, msg.sender, paybackAmount);

    return paybackAmount;
  }
}