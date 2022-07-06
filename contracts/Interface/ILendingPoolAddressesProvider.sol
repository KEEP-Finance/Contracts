// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILendingPoolAddressesProvider {
  event ConfigurationAdminUpdated(address indexed newAddress);
  event EmergencyAdminUpdated(address indexed newAddress);
  event LendingPoolConfiguratorUpdated(address indexed newAddress);
  event PriceOracleUpdated(address indexed newAddress);
  event LendingRateOracleUpdated(address indexed newAddress);
  event AddressSet(bytes32 id, address indexed newAddress);
  event PoolAdded(address pool_address, address configuratorAddress, address lending_pool_cm_address);
  event LendingPoolUpdated(uint id, address pool, address lending_pool_configurator_address, address lending_pool_cm_address);
  event PoolRemoved(address pool_address);
  event SwapRouterUpdated(address dex);

  function getAllPools() external view returns (address[] memory);

  function getLendingPool(uint id) external view returns (address, bool);

  function getLendingPoolID(address pool) external view returns (uint);

  function getLendingPoolConfigurator(address pool) external view returns (address);

  function getLendingPoolCollateralManager(address pool) external view returns (address);

  function setLendingPool(uint id, address pool, address lending_pool_configurator_address, address lending_pool_cm_address) external;

  function addPool(address pool_address, address configurator_address, address cm_address) external;

  function removePool(address pool_address) external;

  function deployAddPool(bytes32 data) external returns (address);

  function setAddress(bytes32 id, address newAddress) external;

  function getAddress(bytes32 id) external view returns (address);

  function getMainAdmin() external view returns (address);

  function setMainAdmin(address admin) external;

  function getEmergencyAdmin() external view returns (address);

  function setEmergencyAdmin(address admin) external;

  function getPriceOracle() external view returns (address);

  function setPriceOracle(address priceOracle) external;

  function getSwapRouter() external view returns (address);

  function setSwapRouter(address dex) external;

  function getOneInch() external view returns (address, address);
}
