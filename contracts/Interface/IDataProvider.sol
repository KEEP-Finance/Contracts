// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {DataTypes} from '../Library/Type/DataTypes.sol';
import {ILendingPoolAddressesProvider} from './ILendingPoolAddressesProvider.sol';

interface IDataProvider {
  struct TokenData {
    string symbol;
    address tokenAddress;
  }

  function getAddressesProvider() external view returns (ILendingPoolAddressesProvider);
  function getAllReservesTokens(uint id) external view returns (TokenData[] memory);
  function getAllATokens(uint id) external view returns (TokenData[] memory);
  function getReserveConfigurationData(uint id, address asset)
    external
    view
    returns (
      DataTypes.ReserveConfiguration memory configuration
    );
  
  function getReserveData(uint id, address asset)
    external
    view
    returns (
      DataTypes.ReserveData memory
    );
  
  function getUserReserveData(uint id, address asset, address user)
    external
    view
    returns (
      uint256 currentKTokenBalance,
      uint256 currentVariableDebt,
      uint256 scaledVariableDebt,
      uint256 liquidityRate,
      bool usageAsCollateralEnabled
    );
  
  function getReserveTokensAddresses(uint id, address asset)
    external
    view
    returns (
      address aTokenAddress,
      address variableDebtTokenAddress
    );
}