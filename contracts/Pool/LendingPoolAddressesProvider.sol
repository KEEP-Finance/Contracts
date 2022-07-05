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
  bytes32 private constant ONEINCH_ROUTER = 'ONEINCH_ROUTER';
  bytes32 private constant ONEINCH_EXECUTOR = 'ONEINCH_EXECUTOR';

  address[] private lending_pool_array;
  mapping(address => address) private lending_pool_configurator_mapping;
  mapping(address => address) private lending_pool_cm_mapping;
  mapping(address => bool) private lending_pool_valid;

  constructor(
    address main_admin,
    address emergency_admin,
    address oracle,
    address swapRouterAddr_,
    address swapExecutorAddr_
  ) {
    _addresses[MAIN_ADMIN] = main_admin;
    _addresses[EMERGENCY_ADMIN] = emergency_admin;
    _addresses[PRICE_ORACLE] = oracle;
    _addresses[ONEINCH_ROUTER] = swapRouterAddr_;
    _addresses[ONEINCH_EXECUTOR] = swapExecutorAddr_;
  }

  function _add_lending_pool(
    address lending_pool_address,
    address lending_pool_configurator_address,
    address lending_pool_cm_address
  ) internal {
    require(lending_pool_valid[lending_pool_address] != true, Errors.GetError(Errors.Error.LENDING_POOL_EXIST));
    lending_pool_valid[lending_pool_address] = true;
    lending_pool_array.push(lending_pool_address);
    lending_pool_configurator_mapping[lending_pool_address] = lending_pool_configurator_address;
    lending_pool_cm_mapping[lending_pool_address] = lending_pool_cm_address;
    emit PoolAdded(lending_pool_address, lending_pool_configurator_address, lending_pool_cm_address);
  }

  function _remove_lending_pool(address lending_pool_address) internal {
    require(lending_pool_valid[lending_pool_address] == true, Errors.GetError(Errors.Error.LENDING_POOL_NONEXIST));
    delete lending_pool_valid[lending_pool_address];
    delete lending_pool_configurator_mapping[lending_pool_address];
    emit PoolRemoved(lending_pool_address);
  }

  function getAllPools() external override view returns (address[] memory) {
    uint pool_length = lending_pool_array.length;
    uint pool_number = 0;
    for (uint i = 0; i < pool_length; i++) {
        address curr_pool_address = lending_pool_array[i];
        if (lending_pool_valid[curr_pool_address] == true) {
            pool_number = pool_number + 1;
        }
    }
    address[] memory all_pools = new address[](pool_number);
    for (uint i = 0; i < pool_length; i++) {
        address curr_pool_address = lending_pool_array[i];
        if (lending_pool_valid[curr_pool_address] == true) {
            pool_number = pool_number - 1;
            all_pools[pool_number] = curr_pool_address;
        }
    }
    return all_pools;
  }

  function addPool(address pool_address, address lending_pool_configurator_address, address lending_pool_cm_address) external override onlyOwner {
    _add_lending_pool(pool_address, lending_pool_configurator_address, lending_pool_cm_address);
  }

  function removePool(address pool_address) external override onlyOwner {
    _remove_lending_pool(pool_address);
  }

  function deployAddPool(bytes32 data) external override onlyOwner returns (address) {
    return address(0);
  }

  /**
   * @dev Returns the address of the LendingPool proxy
   * @return The LendingPool proxy address
   **/
  function getLendingPool(uint id) external view override returns (address, bool) {
    return (lending_pool_array[id], lending_pool_valid[lending_pool_array[id]]);
  }

  function getLendingPoolConfigurator(address pool) external view override returns (address) {
    return lending_pool_configurator_mapping[pool];
  }

  function getLendingPoolCollateralManager(address pool) external view override returns (address) {
    return lending_pool_cm_mapping[pool];
  }

  /**
   * @dev Updates the address of the LendingPool
   * @param pool The new LendingPool implementation
   **/
  function setLendingPool(uint id, address pool, address lending_pool_configurator_address, address cm_address) external override onlyOwner {
    lending_pool_array[id] = pool;
    lending_pool_valid[pool] = true;
    lending_pool_configurator_mapping[pool] = lending_pool_configurator_address;
    lending_pool_cm_mapping[pool] = cm_address;
    emit LendingPoolUpdated(id, pool, lending_pool_configurator_address, cm_address);
  }


  /**
   * @dev Sets an address for an id replacing the address saved in the addresses map
   * IMPORTANT Use this function carefully, as it will do a hard replacement
   * @param id The id
   * @param newAddress The address to set
   */
  function setAddress(bytes32 id, address newAddress) external override onlyOwner {
    _addresses[id] = newAddress;
    emit AddressSet(id, newAddress);
  }

  /**
   * @dev Returns an address by id
   * @return The address
   */
  function getAddress(bytes32 id) public view override returns (address) {
    return _addresses[id];
  }

  /**
   * @dev The functions below are getters/setters of addresses that are outside the context
   * of the protocol hence the upgradable proxy pattern is not used
   **/

  function getMainAdmin() external view override returns (address) {
    return getAddress(MAIN_ADMIN);
  }

  function setMainAdmin(address admin) external override onlyOwner {
    _addresses[MAIN_ADMIN] = admin;
    emit ConfigurationAdminUpdated(admin);
  }

  function getEmergencyAdmin() external view override returns (address) {
    return getAddress(EMERGENCY_ADMIN);
  }

  function setEmergencyAdmin(address emergencyAdmin) external override onlyOwner {
    _addresses[EMERGENCY_ADMIN] = emergencyAdmin;
    emit EmergencyAdminUpdated(emergencyAdmin);
  }

  function getPriceOracle() external view override returns (address) {
    return getAddress(PRICE_ORACLE);
  }

  function setPriceOracle(address priceOracle) external override onlyOwner {
    _addresses[PRICE_ORACLE] = priceOracle;
    emit PriceOracleUpdated(priceOracle);
  }

  function getSwapRouter() external view override returns (address) {
    return getAddress(SWAP_ROUTER);
  }

  function setSwapRouter(address swapRouter) external override onlyOwner {
    _addresses[SWAP_ROUTER] = swapRouter;
    emit SwapRouterUpdated(swapRouter);
  }

  function getOneInch() external view override returns (address, address) {
    return (_addresses[ONEINCH_ROUTER], _addresses[ONEINCH_EXECUTOR]);
  }
}
