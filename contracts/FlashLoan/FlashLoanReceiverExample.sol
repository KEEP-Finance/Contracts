// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '../Dependency/openzeppelin/SafeMath.sol';
import {IERC20} from '../Dependency/openzeppelin/IERC20.sol';
import {SafeERC20} from '../Dependency/openzeppelin/SafeERC20.sol';
import {FlashLoanReceiverBase} from './FlashLoanReceiverBase.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../Interface/ILendingPool.sol';
import {IMockERC20} from '../Mock/IMockERC20.sol';

contract FlashLoanReceiverExample is FlashLoanReceiverBase {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  event ExecutedWithFail(address[] _assets, uint256[] _amounts, uint256[] _premiums);
  event ExecutedWithSuccess(address[] _assets, uint256[] _amounts, uint256[] _premiums);

  bool _failExecution;
  uint256 _amountToApprove;
  bool _simulateEOA;

  function setFailExecutionTransfer(bool fail) public {
    _failExecution = fail;
  }

  function setAmountToApprove(uint256 amountToApprove) public {
    _amountToApprove = amountToApprove;
  }

  function setSimulateEOA(bool flag) public {
    _simulateEOA = flag;
  }

  function amountToApprove() public view returns (uint256) {
    return _amountToApprove;
  }

  function simulateEOA() public view returns (bool) {
    return _simulateEOA;
  }

  constructor(
    ILendingPoolAddressesProvider provider,
    uint poolId
  ) FlashLoanReceiverBase(provider, poolId) {}

  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    if (_failExecution) {
      emit ExecutedWithFail(assets, amounts, premiums);
      return !_simulateEOA;
    }

    for (uint256 i = 0; i < assets.length; i++) {
      //mint to this contract the specific amount
      IMockERC20 token = IMockERC20(assets[i]);

      //check the contract has the specified balance
      require(
        amounts[i] <= IERC20(assets[i]).balanceOf(address(this)),
        'Invalid balance for the contract'
      );

      uint256 amountToReturn =
        (_amountToApprove != 0) ? _amountToApprove : amounts[i].add(premiums[i]);
      //execution does not fail - mint tokens and return them to the _destination

      token.mint(address(this), premiums[i]);

      IERC20(assets[i]).approve(address(LENDING_POOL), amountToReturn);
    }

    emit ExecutedWithSuccess(assets, amounts, premiums);

    return true;
  }
}