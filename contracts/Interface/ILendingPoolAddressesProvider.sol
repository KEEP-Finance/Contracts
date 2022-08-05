// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILendingPoolAddressesProvider {
  event ConfigurationAdminUpdated(address indexed newAddress);
  event EmergencyAdminUpdated(address indexed newAddress);
  event LendingPoolConfiguratorUpdated(address indexed newAddress);
  event PriceOracleUpdated(address indexed newAddress);
  event LendingRateOracleUpdated(address indexed newAddress);
  event AddressSet(bytes32 id, address indexed newAddress);
  event PoolAdded(address pool_address, address configuratorAddress);
  event LendingPoolUpdated(uint id, address pool, address lending_pool_configurator_address);
  event PoolRemoved(address pool_address);
  event SwapRouterUpdated(address dex);

  function getAllPools() external view returns (address[] memory);

  /**
   * @dev Returns the address of the LendingPool by id
   * @return The LendingPool address, if pool is valid
   **/
  function getLendingPool(uint id) external view returns (address, bool);

  function getLendingPoolID(address pool) external view returns (uint);

  function getLendingPoolConfigurator(address pool) external view returns (address);

  /**
   * @dev Updates the address of the LendingPool
   * @param pool The new LendingPool implementation
   **/
  function setLendingPool(uint id, address pool, address poolConfiguratorAddress) external;

  function addPool(address poolAddress, address poolConfiguratorAddress) external;

  function removePool(address poolAddress) external;

  /**
   * @dev Sets an address for an id replacing the address saved in the addresses map
   * IMPORTANT Use this function carefully, as it will do a hard replacement
   * @param id The id
   * @param newAddress The address to set
   */
  function setAddress(bytes32 id, address newAddress) external;

  /**
   * @dev Returns an address by id
   * @return The address
   */
  function getAddress(bytes32 id) external view returns (address);

  function getMainAdmin() external view returns (address);

  function setMainAdmin(address admin) external;

  function getEmergencyAdmin() external view returns (address);

  function setEmergencyAdmin(address admin) external;

  function getPriceOracle() external view returns (address);

  function setPriceOracle(address priceOracleAddress) external;

  function getSwapRouter() external view returns (address);

  function setSwapRouter(address dex) external;
}
