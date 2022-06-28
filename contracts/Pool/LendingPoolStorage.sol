// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {ReserveLogic} from '../libraries/logic/ReserveLogic.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {DataTypes} from '../Library/Type/DataTypes.sol';
import {ReserveLogic} from '../Library/Logic/ReserveLogic.sol';
import {ReserveLogic} from '../Library/Logic/ReserveLogic.sol';

contract LendingPoolStorage {
// using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
// using UserConfiguration for DataTypes.UserConfigurationMap;

  ILendingPoolAddressesProvider internal _addressesProvider;

  // reserves, mapped by asset address
  mapping(address => DataTypes.ReserveData) internal _reserves;
  // user configs, mapped by user address
  mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

  // list of positions, structured as a mapping for gas savings
  mapping(uint256 => DataTypes.TraderPosition) internal _positionsList;
  // the number of historical positions
  uint256 internal _positionsCount;
  // the mapping of position of a user, for reading
  mapping(address => DataTypes.TraderPosition[]) internal _traderPositionMapping;

  // the list of the available reserves, structured as a mapping for gas savings reasons
  mapping(uint256 => address) internal _reservesList;
  // the number of initialized reserves
  uint256 internal _reservesCount;
  // the list of users who have supplied TODO: automatically remove stale users
  mapping(uint256 => address) internal _usersList;
  // if the user has been encountered before
  mapping(address => bool) internal _userActive;
  // the number of users
  uint256 internal _usersCount;
  // the list of traders who have opened positions TODO: automatically remove stale traders
  mapping(uint256 => address) internal _tradersList;
  // if the trader has been encountered before
  mapping(address => bool) internal _traderActive;
  // the number of traders
  uint256 internal _tradersCount;
  // if lending pool is paused or not
  bool internal _paused;
  // the maximum number of reserves
  uint256 internal _maxNumberOfReserves;
  // whether or not the pool is main pool
  bool internal _isMainPool;
  // the liquidation threshold for positions, in ray
  uint256 internal _positionLiquidationThreshold;
  // the maximum lending leverage, in ray
  uint256 internal _maximumLeverage;
}
