// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {Address} from '../../dependencies/openzeppelin/contracts/Address.sol';
import {Ownable} from '../../dependencies/openzeppelin/contracts/Ownable.sol';
import {Helpers} from '../libraries/helpers/Helpers.sol';
import {Errors} from '../libraries/helpers/Errors.sol';
import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {PercentageMath} from '../libraries/math/PercentageMath.sol';
import {ILendingPoolAggregator} from '../../interfaces/ILendingPoolAggregator.sol';
import {VersionedInitializable} from '../libraries/aave-upgradeability/VersionedInitializable.sol';

contract LendingPoolAggregator is ILendingPoolAggregator, VersionedInitializable, Ownable {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;

  address[] private lending_pool_array;
  mapping(address => bool) private lending_pool_valid;

  constructor () public Ownable() {

  }

  function getRevision() internal pure override returns (uint256) {
    return 0;
  }

  function _add_lending_pool(address lending_pool_address) internal {
    require(lending_pool_valid[lending_pool_address] != true, "");
    lending_pool_valid[lending_pool_address] = true;
    lending_pool_array.push(lending_pool_address);
  }

  function _remove_lending_pool(address lending_pool_address) internal {
    require(lending_pool_valid[lending_pool_address] == true, "");
    delete lending_pool_valid[lending_pool_address];
  }

  function GetAllPools() external override view returns (address[] memory) {
    uint pool_length = lending_pool_array.length;
    uint pool_number = 0;
    for (uint i = 0; i < pool_length; i++) {
        address curr_pool_address = lending_pool_array[i];
        if (lending_pool_valid[curr_pool_address] == true) {
            pool_number.add(1);
        }
    }
    address[] memory all_pools = new address[](pool_number);
    for (uint i = 0; i < pool_length; i++) {
        address curr_pool_address = lending_pool_array[i];
        if (lending_pool_valid[curr_pool_address] == true) {
            pool_number.sub(1);
            all_pools[pool_number] = curr_pool_address;
        }
    }
    return all_pools;
  }

  function AddPool(address pool_address) external override {
    _add_lending_pool(pool_address);
  }

  function RemovePool(address pool_address) external override {
    _remove_lending_pool(pool_address);
  }
}