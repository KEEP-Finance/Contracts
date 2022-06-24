// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library DataTypes {
  struct ReserveData {
    // loan-to-value
    uint16 ltv;
    // the liquidation threshold
    uint16 liquidationThreshold;
    // the liquidation bonus
    uint16 liquidationBonus;
    // the decimals
    uint8 decimals;
    // reserve is active
    bool active;
    // reserve is frozen
    bool frozen;
    // borrowing is enabled
    bool borrowingEnabled;
    // reserve factor
    uint16 reserveFactor;
    // the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    // variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    // the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    // the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    // the timestamp 
    uint40 lastUpdateTimestamp;
    // tokens addresses
    address kTokenAddress;
    address dTokenAddress;
    // address of the interest rate strategy
    address interestRateStrategyAddress;
    // the id of the reserve
    uint256 id;
  }

  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }

  struct UserConfigurationMap {
    // uint256 data;
    mapping(uint256 => bool) reserve_is_collateral;
    mapping(uint256 => bool) reserve_for_borrowing;
  }

  enum InterestRateMode {NONE, VARIABLE}
}
