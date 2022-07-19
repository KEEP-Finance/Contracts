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
  mapping(address => address) private lendingPoolCollateralManager;
  mapping(address => bool) private lendingPoolValid;

  constructor(
    address main_admin,
    address emergency_admin,
    address oracle,
    address swapRouterAddr_
  ) {
    _addresses[MAIN_ADMIN] = main_admin;
    _addresses[EMERGENCY_ADMIN] = emergency_admin;
    _addresses[PRICE_ORACLE] = oracle;
    _addresses[SWAP_ROUTER] = swapRouterAddr_;
  }

  function _add_lending_pool(
    address lending_pool_address,
    address lending_pool_configurator_address,
    address lending_pool_cm_address
  ) internal {
    require(lendingPoolValid[lending_pool_address] != true, Errors.GetError(Errors.Error.LENDING_POOL_EXIST));
    lendingPoolValid[lending_pool_address] = true;
    lendingPoolID[lending_pool_address] = lendingPoolAddressArray.length;
    lendingPoolAddressArray.push(lending_pool_address);
    lendingPoolConfigurator[lending_pool_address] = lending_pool_configurator_address;
    lendingPoolCollateralManager[lending_pool_address] = lending_pool_cm_address;
    emit PoolAdded(lending_pool_address, lending_pool_configurator_address, lending_pool_cm_address);
  }

  function _remove_lending_pool(address lending_pool_address) internal {
    require(lendingPoolValid[lending_pool_address] == true, Errors.GetError(Errors.Error.LENDING_POOL_NONEXIST));
    delete lendingPoolValid[lending_pool_address];
    delete lendingPoolConfigurator[lending_pool_address];
    delete lendingPoolCollateralManager[lending_pool_address];
    delete lendingPoolID[lending_pool_address];
    emit PoolRemoved(lending_pool_address);
  }

  function getAllPools() external override view returns (address[] memory) {
    uint pool_length = lendingPoolAddressArray.length;
    uint pool_number = 0;
    for (uint i = 0; i < pool_length; i++) {
        address curr_pool_address = lendingPoolAddressArray[i];
        if (lendingPoolValid[curr_pool_address] == true) {
            pool_number = pool_number + 1;
        }
    }
    address[] memory all_pools = new address[](pool_number);

    uint idx = 0;
    for (uint i = 0; i < pool_length; i++) {
        address curr_pool_address = lendingPoolAddressArray[i];
        if (lendingPoolValid[curr_pool_address] == true) {
            all_pools[idx] = curr_pool_address;
            idx = idx + 1;
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
    return (lendingPoolAddressArray[id], lendingPoolValid[lendingPoolAddressArray[id]]);
  }

  function getLendingPoolID(address pool) external view override returns (uint) {
    return lendingPoolID[pool];
  }

  function getLendingPoolConfigurator(address pool) external view override returns (address) {
    return lendingPoolConfigurator[pool];
  }

  function getLendingPoolCollateralManager(address pool) external view override returns (address) {
    return lendingPoolCollateralManager[pool];
  }

  /**
   * @dev Updates the address of the LendingPool
   * @param pool The new LendingPool implementation
   **/
  function setLendingPool(uint id, address pool, address lending_pool_configurator_address, address cm_address) external override onlyOwner {
    lendingPoolAddressArray[id] = pool;
    lendingPoolValid[pool] = true;
    lendingPoolConfigurator[pool] = lending_pool_configurator_address;
    lendingPoolCollateralManager[pool] = cm_address;
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

}
