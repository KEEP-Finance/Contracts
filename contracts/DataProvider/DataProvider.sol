// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {MathUtils} from '../Library/Math/MathUtils.sol';
import {WadRayMath} from '../Library/Math/WadRayMath.sol';
import {PercentageMath} from '../Library/Math/PercentageMath.sol';
import {IDToken} from '../Interface/IDToken.sol';
import {IKToken} from '../Interface/IKToken.sol';
import {ILendingPool} from '../Interface/ILendingPool.sol';
import {IPriceOracleGetter} from '../Interface/IPriceOracleGetter.sol';
import {IDataProvider} from '../Interface/IDataProvider.sol';
import {Errors} from '../Library/Helper/Errors.sol';
import {IERC20} from '../Dependency/openzeppelin/IERC20.sol';
import {IERC20Detailed} from '../Dependency/openzeppelin/IERC20Detailed.sol';
import {Address} from '../Dependency/openzeppelin/Address.sol';
import {SafeMath} from '../Dependency/openzeppelin/SafeMath.sol';
import {SafeERC20} from '../Dependency/openzeppelin/SafeERC20.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {DataTypes} from '../Library/Type/DataTypes.sol';
import {GenericLogic} from '../Library/Logic/GenericLogic.sol';
import {ValidationLogic} from '../Library/Logic/ValidationLogic.sol';
import {ReserveLogic} from '../Library/Logic/ReserveLogic.sol';

contract DataProvider is IDataProvider {
  using WadRayMath for uint256;

  ILendingPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

  constructor(ILendingPoolAddressesProvider addressesProvider) {
    ADDRESSES_PROVIDER = addressesProvider;
  }

  function getAllPoolData() external view override returns (PoolData[] memory) {
    address[] memory pools = ADDRESSES_PROVIDER.getAllPools();
    PoolData[] memory poolsData = new PoolData[](pools.length);
    for (uint i = 0; i < pools.length; i++) {
      address pool_address = pools[i];
      poolsData[i] = PoolData(
          pool_address,
          ADDRESSES_PROVIDER.getLendingPoolID(pool_address),
          ILendingPool(pool_address).name(),
          ILendingPool(pool_address).paused()
        );
    }
    return poolsData;
  }

  function getAddressesProvider() external view override returns (ILendingPoolAddressesProvider) {
    return ADDRESSES_PROVIDER;
  }

  function getAllReservesTokens(uint id) external view override returns (TokenData[] memory) {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    ILendingPool pool = ILendingPool(pool_address);
    address[] memory reserves = pool.getReservesList();
    TokenData[] memory reservesTokens = new TokenData[](reserves.length);
    for (uint256 i = 0; i < reserves.length; i++) {
      reservesTokens[i] = TokenData({
        symbol: IERC20Detailed(reserves[i]).symbol(),
        tokenAddress: reserves[i]
      });
    }
    return reservesTokens;
  }

  function getAllATokens(uint id) external view override returns (TokenData[] memory) {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    ILendingPool pool = ILendingPool(pool_address);
    address[] memory reserves = pool.getReservesList();
    TokenData[] memory aTokens = new TokenData[](reserves.length);
    for (uint256 i = 0; i < reserves.length; i++) {
      DataTypes.ReserveData memory reserveData = pool.getReserveData(reserves[i]);
      aTokens[i] = TokenData({
        symbol: IERC20Detailed(reserveData.kTokenAddress).symbol(),
        tokenAddress: reserveData.kTokenAddress
      });
    }
    return aTokens;
  }

  function getReserveConfigurationData(uint id, address asset)
    external
    view
    override
    returns (
      DataTypes.ReserveConfiguration memory configuration
    )
  {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    configuration =
      ILendingPool(pool_address).getConfiguration(asset);
  }

  function getReserveData(uint id, address asset)
    external
    view
    override
    returns (
      DataTypes.ReserveData memory
    )
  {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    DataTypes.ReserveData memory reserve =
      ILendingPool(pool_address).getReserveData(asset);
    return reserve;
  }

  function getAllReserveData(uint id)
    external
    view
    override
    returns (
      DataTypes.ReserveData[] memory
    )
  {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    ILendingPool pool = ILendingPool(pool_address);
    address[] memory reserves = pool.getReservesList();

    DataTypes.ReserveData[] memory reservesData = new DataTypes.ReserveData[](reserves.length);
    for (uint256 i = 0; i < reserves.length; i++) {
      reservesData[i] = pool.getReserveData(reserves[i]);
    }

    return reservesData;
  }

  function getUserReserveData(uint id, address asset, address user)
    external
    view
    override
    returns (
      uint256 currentKTokenBalance,
      uint256 currentVariableDebt,
      uint256 scaledVariableDebt,
      uint256 liquidityRate,
      bool usageAsCollateralEnabled
    )
  {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    DataTypes.ReserveData memory reserve =
      ILendingPool(pool_address).getReserveData(asset);

    (bool isUsingAsCollateral,) =
      ILendingPool(pool_address).getUserConfiguration(user, reserve.id);

    currentKTokenBalance = IERC20Detailed(reserve.kTokenAddress).balanceOf(user);
    currentVariableDebt = IERC20Detailed(reserve.dTokenAddress).balanceOf(user);
    scaledVariableDebt = IDToken(reserve.dTokenAddress).scaledBalanceOf(user);
    liquidityRate = reserve.currentLiquidityRate;
    usageAsCollateralEnabled = isUsingAsCollateral;
  }

  function getReserveTokensAddresses(uint id, address asset)
    external
    view
    override
    returns (
      address aTokenAddress,
      address variableDebtTokenAddress
    )
  {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    DataTypes.ReserveData memory reserve =
      ILendingPool(pool_address).getReserveData(asset);

    return (
      reserve.kTokenAddress,
      reserve.dTokenAddress
    );
  }

  function getTraderPositions(uint id, address trader) external view override returns (DataTypes.TraderPosition[] memory positions) {
    (address pool_address,) = ADDRESSES_PROVIDER.getLendingPool(id);
    ILendingPool pool = ILendingPool(pool_address);
    return pool.getTraderPositions(trader);
  }

}