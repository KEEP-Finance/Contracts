// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "../Interface/ILendingPool.sol";
import "../Interface/IDataProvider.sol";
import "../Interface/1inch/IAggregationRouterV4.sol";
import "../Library/Logic/GenericLogic.sol";

contract PositionKeeper is KeeperCompatibleInterface {
    ILendingPool private LendingPool;
    IDataProvider private DataProvider;
    address private collateralToken;
    uint256 private poolId;
    address private owner;

    constructor(
        address lendingPool_,
        address dataProvider_,
        address collateralToken_,
        uint256 poolId_
    ) {
        LendingPool = ILendingPool(lendingPool_);
        DataProvider = IDataProvider(dataProvider_);
        poolId = poolId_;
        collateralToken = collateralToken_;
        owner = msg.sender;
    }

    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bool runCheck = _shouldRun();
        upkeepNeeded = (runCheck);
        performData = checkData;
    }

    function performUpkeep(bytes calldata performData) external override {
        uint length = LendingPool.getUsersList().length;
        for (uint i = 0; i < length; i++) {
            address userToCheck = LendingPool.getUsersList()[i];
            uint positionLength = LendingPool.getTraderPositions(userToCheck).length;
            for (uint j = 0; j < positionLength; j++) {
                DataTypes.TraderPosition memory position = LendingPool.getTraderPositions(userToCheck)[j];
                if (!position.isOpen) continue;
                bool needsCheck = checkUnique(position.id);
                if (needsCheck) {
                    performUnique(
                        position.id
                    );
                    return;
                }
            }
        }
    }

    function performUnique(
        uint id
    ) internal {
        LendingPool.liquidationCallPosition(
            id
        );
    }

    function _shouldRun() internal view returns (bool runCheck) {
        runCheck = false;
        uint length = LendingPool.getUsersList().length;

        for (uint i = 0; i < length; i++) {
            address userToCheck = LendingPool.getUsersList()[i];
            uint positionLength = LendingPool.getTraderPositions(userToCheck).length;
            for (uint j = 0; j < positionLength; j++) {
                DataTypes.TraderPosition memory position = LendingPool.getTraderPositions(userToCheck)[j];
                if (!position.isOpen) continue;
                bool needsCheck = checkUnique(position.id);
                if (needsCheck) {
                    runCheck = true;
                    break;
                }
            }
        }
    }

    function checkUnique(uint256 id)
        internal
        view
        returns (bool runCheck)
    {
        (
            /* int256 pnl */,
            uint256 healthFactor
        ) = LendingPool.getPositionData(id);

        if (healthFactor < GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            runCheck = true;
        }
    }
}