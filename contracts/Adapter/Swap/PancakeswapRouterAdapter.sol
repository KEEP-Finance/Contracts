// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISwapRouter} from '../../Interface/ISwapRouter.sol';
import {Ownable} from '../../Dependency/openzeppelin/Ownable.sol';
import {IPancakeRouter01} from '../../Interface/PancakeSwap/IPancakeRouter01.sol';
import {IPancakeRouter02} from '../../Interface/PancakeSwap/IPancakeRouter02.sol';

contract PancakeswapRouterAdapter is ISwapRouter, Ownable {
  IPancakeRouter01 internal pancakeRouter01;
  IPancakeRouter02 internal pancakeRouter02;

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
    path[0] = tokenIn;
    path[1] = tokenOut;
    // TODO: approve
    _amountIn = pancakeRouter01.swapTokensForExactTokens(
      amountOut,
      amountInMax,
      path,
      msg.sender,
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
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = tokenOut;
    // TODO: approve
    _amountIn = amountIn;
    _amountOut = pancakeRouter01.swapExactTokensForTokens(
      amountIn,
      amountOutMin,
      path,
      msg.sender,
      deadline
    )[0];
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