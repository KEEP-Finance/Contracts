// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface ILendingPoolAggregator {
  function GetAllPools() external view returns (address[] memory);
  function AddPool(address pool_address) external;
  function RemovePool(address pool_address) external;
}