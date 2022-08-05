// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '../Dependency/openzeppelin/Ownable.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {Errors} from '../Library/Helper/Errors.sol';

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Aave Governance
 * @author Aave
 **/
contract LendingPoolAddressesProvider is Ownable, ILendingPoolAddressesProvider {
  mapping(bytes32 => address) private _addresses;

  bytes32 private constant MAIN_ADMIN = 'MAIN_ADMIN';
  bytes32 private constant EMERGENCY_ADMIN = 'EMERGENCY_ADMIN';
  bytes32 private constant PRICE_ORACLE = 'PRICE_ORACLE';
  bytes32 private constant SWAP_ROUTER = 'SWAP_ROUTER';

  address[] private lendingPoolAddressArray;
  mapping(address => uint) private lendingPoolID;
  mapping(address => address) private lendingPoolConfigurator;
  mapping(address => bool) private lendingPoolValid;

  constructor(
    address mainAdmin,
    address emergencyAdmin,
    address oracleAddress,
    address swapRouterAddress
  ) {
    _addresses[MAIN_ADMIN] = mainAdmin;
    _addresses[EMERGENCY_ADMIN] = emergencyAdmin;
    _addresses[PRICE_ORACLE] = oracleAddress;
    _addresses[SWAP_ROUTER] = swapRouterAddress;
  }

  function _addPool(
    address poolAddress,
    address poolConfiguratorAddress
  ) internal {
    require(lendingPoolValid[poolAddress] != true, Errors.GetError(Errors.Error.LENDING_POOL_EXIST));
    lendingPoolValid[poolAddress] = true;
    lendingPoolID[poolAddress] = lendingPoolAddressArray.length;
    lendingPoolAddressArray.push(poolAddress);
    lendingPoolConfigurator[poolAddress] = poolConfiguratorAddress;
    emit PoolAdded(poolAddress, poolConfiguratorAddress);
  }

  function _removePool(address poolAddress) internal {
    require(lendingPoolValid[poolAddress] == true, Errors.GetError(Errors.Error.LENDING_POOL_NONEXIST));
    delete lendingPoolValid[poolAddress];
    delete lendingPoolConfigurator[poolAddress];
    delete lendingPoolID[poolAddress];
    emit PoolRemoved(poolAddress);
  }

  function getAllPools() external override view returns (address[] memory) {
    uint cachedPoolLength = lendingPoolAddressArray.length;
    uint poolNumber = 0;
    for (uint i = 0; i < cachedPoolLength; i++) {
        address cachedPoolAddress = lendingPoolAddressArray[i];
        if (lendingPoolValid[cachedPoolAddress] == true) {
            poolNumber = poolNumber + 1;
        }
    }
    address[] memory validPools = new address[](poolNumber);

    uint idx = 0;
    for (uint i = 0; i < cachedPoolLength; i++) {
        address cachedPoolAddress = lendingPoolAddressArray[i];
        if (lendingPoolValid[cachedPoolAddress] == true) {
            validPools[idx] = cachedPoolAddress;
            idx = idx + 1;
        }
    }
    return validPools;
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function addPool(address poolAddress, address poolConfiguratorAddress) external override onlyOwner {
    _addPool(poolAddress, poolConfiguratorAddress);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function removePool(address poolAddress) external override onlyOwner {
    _removePool(poolAddress);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getLendingPool(uint id) external view override returns (address, bool) {
    return (lendingPoolAddressArray[id], lendingPoolValid[lendingPoolAddressArray[id]]);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getLendingPoolID(address pool) external view override returns (uint) {
    return lendingPoolID[pool];
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getLendingPoolConfigurator(address pool) external view override returns (address) {
    return lendingPoolConfigurator[pool];
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function setLendingPool(uint id, address pool, address poolConfiguratorAddress) external override onlyOwner {
    lendingPoolAddressArray[id] = pool;
    lendingPoolValid[pool] = true;
    lendingPoolConfigurator[pool] = poolConfiguratorAddress;
    emit LendingPoolUpdated(id, pool, poolConfiguratorAddress);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function setAddress(bytes32 id, address newAddress) external override onlyOwner {
    _addresses[id] = newAddress;
    emit AddressSet(id, newAddress);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getAddress(bytes32 id) public view override returns (address) {
    return _addresses[id];
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getMainAdmin() external view override returns (address) {
    return getAddress(MAIN_ADMIN);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function setMainAdmin(address admin) external override onlyOwner {
    _addresses[MAIN_ADMIN] = admin;
    emit ConfigurationAdminUpdated(admin);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getEmergencyAdmin() external view override returns (address) {
    return getAddress(EMERGENCY_ADMIN);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function setEmergencyAdmin(address emergencyAdmin) external override onlyOwner {
    _addresses[EMERGENCY_ADMIN] = emergencyAdmin;
    emit EmergencyAdminUpdated(emergencyAdmin);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getPriceOracle() external view override returns (address) {
    return getAddress(PRICE_ORACLE);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function setPriceOracle(address priceOracleAddress) external override onlyOwner {
    _addresses[PRICE_ORACLE] = priceOracleAddress;
    emit PriceOracleUpdated(priceOracleAddress);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function getSwapRouter() external view override returns (address) {
    return getAddress(SWAP_ROUTER);
  }

  /// @inheritdoc ILendingPoolAddressesProvider
  function setSwapRouter(address swapRouter) external override onlyOwner {
    _addresses[SWAP_ROUTER] = swapRouter;
    emit SwapRouterUpdated(swapRouter);
  }

}
