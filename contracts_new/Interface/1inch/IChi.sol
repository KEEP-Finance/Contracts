// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../Dependency/openzeppelin/IERC20.sol";

/// @title Interface for CHI gas token
interface IChi is IERC20 {
    function mint(uint256 value) external;
    function free(uint256 value) external returns (uint256 freed);
    function freeFromUpTo(address from, uint256 value) external returns (uint256 freed);
}