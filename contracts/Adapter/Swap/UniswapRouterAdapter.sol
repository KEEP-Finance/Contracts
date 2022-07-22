// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKSwapRouter} from '../../Interface/IKSwapRouter.sol';
import {ISwapRouter} from '../../Interface/Uniswap/ISwapRouter.sol';
import {Ownable} from '../../Dependency/openzeppelin/Ownable.sol';
import {IERC20} from '../../Dependency/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../Dependency/openzeppelin/SafeERC20.sol';

contract UniswapRouterAdapter is IKSwapRouter, Ownable {
  using SafeERC20 for IERC20;

  ISwapRouter internal uniswapSwapRouter;
  mapping(address => bool) assetIsApproved;

  constructor(address _uniswapSwapRouter) {
    uniswapSwapRouter = ISwapRouter(_uniswapSwapRouter);
  }

  function SwapTokensForExactTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    uint256 amountInMax,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    // approve
    if (assetIsApproved[tokenIn] != true) {
      IERC20(tokenIn).safeIncreaseAllowance(
        address(uniswapSwapRouter),
        type(uint256).max
      );
      assetIsApproved[tokenIn] = true;
    }

    ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
    tokenIn, // address tokenIn;
    tokenOut, // address tokenOut;
    3000, // uint24 fee;
    recipient, // address recipient;
    type(uint256).max, // uint256 deadline;
    amountOut, // uint256 amountOut;
    amountInMax, // uint256 amountInMaximum;
    0 // uint160 sqrtPriceLimitX96;
    );
    _amountIn = uniswapSwapRouter.exactOutputSingle(params);
    _amountOut = amountOut;
  }

  function SwapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    // approve
    if (assetIsApproved[tokenIn] != true) {
      IERC20(tokenIn).safeIncreaseAllowance(
        address(uniswapSwapRouter),
        type(uint256).max
      );
      assetIsApproved[tokenIn] = true;
    }

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
      tokenIn, // address tokenIn;
      tokenOut, // address tokenOut;
      3000, // uint24 fee;
      recipient, // address recipient;
      type(uint256).max, // uint256 deadline;
      amountIn, // uint256 amountIn;
      amountOutMin, // uint256 amountOutMinimum;
      0 // uint160 sqrtPriceLimitX96;
    );
    _amountIn = amountIn;
    _amountOut = uniswapSwapRouter.exactInputSingle(params);
  }
  
  function GetQuote(
    uint amountA,
    uint reserveA,
    uint reserveB
  ) external view override returns (uint amountB) {
    
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