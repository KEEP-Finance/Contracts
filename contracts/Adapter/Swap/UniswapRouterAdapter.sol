// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKSwapRouter} from '../../Interface/IKSwapRouter.sol';
import {ISwapRouter} from '../../Interface/Uniswap/ISwapRouter.sol';
import {Ownable} from '../../Dependency/openzeppelin/Ownable.sol';

contract UniswapRouterAdapter is IKSwapRouter, Ownable {
  ISwapRouter internal uniswapSwapRouter;
  constructor(address _uniswapSwapRouter) {
    uniswapSwapRouter = ISwapRouter(_uniswapSwapRouter);
  }

  function SwapTokensForExactTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
    tokenIn, // address tokenIn;
    tokenOut, // address tokenOut;
    3000, // uint24 fee;
    recipient, // address recipient;
    type(uint256).max, // uint256 deadline;
    amountOut, // uint256 amountOut;
    type(uint256).max, // uint256 amountInMaximum;
    0 // uint160 sqrtPriceLimitX96;
    );
    _amountIn = uniswapSwapRouter.exactOutputSingle(params);
    _amountOut = amountOut;
  }

  function SwapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
      tokenIn, // address tokenIn;
      tokenOut, // address tokenOut;
      3000, // uint24 fee;
      recipient, // address recipient;
      type(uint256).max, // uint256 deadline;
      amountIn, // uint256 amountIn;
      0, // uint256 amountOutMinimum;
      0 // uint160 sqrtPriceLimitX96;
    );
    _amountIn = amountIn;
    _amountOut = uniswapSwapRouter.exactInputSingle(params);
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