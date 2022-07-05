// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IKSwapRouter {
  function SwapTokensForExactTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    address recipient
  ) external returns (uint256 _amountIn, uint256 _amountOut);

  function SwapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address recipient
  ) external returns (uint256 _amountIn, uint256 _amountOut);

  function GetQuote(uint amountA, uint reserveA, uint reserveB) external view returns (uint amountB);

  /**
   * @dev get the relative price of price A / price B, in wad
   * @param tokenA the address of first token
   * @param tokenB the address of second token
   * @return price
   */ 
  function GetRelativePrice(
    address tokenA,
    address tokenB
  ) external view returns (uint256);

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
  ) external view returns (uint256);
}