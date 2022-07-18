// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IKSwapRouter} from '../Interface/IKSwapRouter.sol';
import {IMockERC20} from './IMockERC20.sol';
import {IPriceOracleGetter} from '../Interface/IPriceOracleGetter.sol';
import {MathUtils} from '../Library/Math/MathUtils.sol';
import {WadRayMath} from '../Library/Math/WadRayMath.sol';

contract MockSwap is IKSwapRouter {
  using WadRayMath for uint256;

  IPriceOracleGetter private _oracle;

  constructor(address oracle) {
    _oracle = IPriceOracleGetter(oracle);
  }

  function SwapTokensForExactTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    IMockERC20(tokenOut).faucet(address(this), amountOut);
    _amountIn = 10**IMockERC20(tokenIn).decimals();
    _amountIn = (_amountIn * amountOut * _oracle.getAssetPrice(tokenOut)).wadDiv(_oracle.getAssetPrice(tokenIn));
    _amountIn = _amountIn / (10**IMockERC20(tokenOut).decimals());
    _amountOut = amountOut;
    IMockERC20(tokenIn).transfer(recipient, IMockERC20(tokenIn).balanceOf(address(this)));
    IMockERC20(tokenOut).transfer(recipient, amountOut);
  }

  function SwapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address recipient
  ) external override returns (uint256 _amountIn, uint256 _amountOut) {
    
    _amountOut = 10**IMockERC20(tokenOut).decimals();
    _amountOut = (_amountOut * amountIn * _oracle.getAssetPrice(tokenIn)).wadDiv(_oracle.getAssetPrice(tokenOut));
    _amountOut = _amountOut / (10**IMockERC20(tokenIn).decimals());
    _amountIn = amountIn;
    IMockERC20(tokenOut).faucet(address(this), _amountOut);
    IMockERC20(tokenOut).transfer(recipient, _amountOut);
  }

  function GetQuote(uint amountA, uint reserveA, uint reserveB)
    external
    view
    override
    returns (uint amountB)
  {

  }

  function GetRelativePrice(
    address tokenA,
    address tokenB
  ) external view override returns (uint256) {

  }

  function GetRelativeTWAP(
    address tokenA,
    address tokenB,
    uint256 timeInterval
  ) external view override returns (uint256) {

  }
}