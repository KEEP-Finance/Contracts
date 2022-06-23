pragma solidity 0.6.12;

import {IChi} from "./IChi.sol";

/// @title Interface for calculating CHI discounts
interface IGasDiscountExtension {
    function calculateGas(uint256 gasUsed, uint256 flags, uint256 calldataLength) external view returns (IChi, uint256);
}