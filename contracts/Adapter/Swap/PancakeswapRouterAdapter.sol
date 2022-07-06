// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKSwapRouter} from '../../Interface/IKSwapRouter.sol';
import {Ownable} from '../../Dependency/openzeppelin/Ownable.sol';
import {IERC20} from '../../Dependency/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../Dependency/openzeppelin/SafeERC20.sol';
import {IPancakeRouter01} from '../../Interface/PancakeSwap/IPancakeRouter01.sol';
import {IPancakeRouter02} from '../../Interface/PancakeSwap/IPancakeRouter02.sol';

contract PancakeswapRouterAdapter is IKSwapRouter, Ownable {
  using SafeERC20 for IERC20;

  IPancakeRouter01 internal pancakeRouter01;
  IPancakeRouter02 internal pancakeRouter02;

  mapping(address => bool) assetIsApproved;

  constructor(
    address _router01,
    address _router02
  ) {
    pancakeRouter01 = IPancakeRouter01(_router01);
    pancakeRouter02 = IPancakeRouter02(_router02);
  }

  function SwapTokensForExactTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    uint256 deadline = type(uint256).max;
    uint256 amountInMax = type(uint256).max;
    address[] memory path = new address[](2);
    // TODO: check
    path[0] = tokenIn;
    path[1] = tokenOut;
    // approve
    if (assetIsApproved[tokenIn] != true) {
      IERC20(tokenIn).safeIncreaseAllowance(
        address(pancakeRouter01),
        type(uint256).max
      );
      assetIsApproved[tokenIn] = true;
    }
    _amountIn = pancakeRouter01.swapTokensForExactTokens(
      amountOut,
      amountInMax,
      path,
      recipient,
      deadline
    )[0];
    _amountOut = amountOut;
  }

  function SwapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    uint256 deadline = type(uint256).max;
    uint256 amountOutMin = 0;
    // TODO: check
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = tokenOut;
    // approve
    if (assetIsApproved[tokenIn] != true) {
      IERC20(tokenIn).safeIncreaseAllowance(
        address(pancakeRouter01),
        type(uint256).max
      );
      assetIsApproved[tokenIn] = true;
    }
    _amountIn = amountIn;
    _amountOut = pancakeRouter01.swapExactTokensForTokens(
      amountIn,
      amountOutMin,
      path,
      recipient,
      deadline
    )[0];
  }

  function GetQuote(
    uint amountA,
    uint reserveA,
    uint reserveB
  ) external view override returns (uint amountB) {
    return pancakeRouter01.quote(amountA, reserveA, reserveB);
  }

  /**
   * @dev get the relative price of price A / price B, in wad
   * @param tokenA the address of first token
   * @param tokenB the address of second token
   * @return price
   */ 
  function GetRelativePrice(
    address tokenA,
    address tokenB
  ) external view override returns (uint256) {

  }

  /**
   * @dev get the time-weighted average relative price of price A / price B, in wad
   * @param tokenA the address of first token
   * @param tokenB the address of second token
   * @return price
   */ 
  function GetRelativeTWAP(
    address tokenA,
    address tokenB,
    uint256 timeInterval
  ) external view override returns (uint256) {

  }
}