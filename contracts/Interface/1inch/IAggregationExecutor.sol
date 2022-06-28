// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGasDiscountExtension} from "./IGasDiscountExtension.sol";

/// @title Interface for making arbitrary calls during swap
interface IAggregationExecutor is IGasDiscountExtension {
    /// @notice Make calls on `msgSender` with specified data
    function callBytes(address msgSender, bytes calldata data) external payable;  // 0x2636f7f8
}
