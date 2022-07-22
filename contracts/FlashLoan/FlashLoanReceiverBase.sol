// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '../Dependency/openzeppelin/SafeMath.sol';
import {IERC20} from '../Dependency/openzeppelin/IERC20.sol';
import {SafeERC20} from '../Dependency/openzeppelin/SafeERC20.sol';
import {IFlashLoanReceiver} from '../Interface/IFlashLoanReceiver.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../Interface/ILendingPool.sol';

abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  ILendingPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
  ILendingPool public immutable override LENDING_POOL;

  constructor(
    ILendingPoolAddressesProvider provider,
    uint poolId
  ) {
    ADDRESSES_PROVIDER = provider;
    (address poolAddress, bool valid) = provider.getLendingPool(poolId);
    require(valid == true, "Pool not valid");
    LENDING_POOL = ILendingPool(poolAddress);
  }
}