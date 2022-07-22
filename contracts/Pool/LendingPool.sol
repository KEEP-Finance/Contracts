// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {MathUtils} from '../Library/Math/MathUtils.sol';
import {WadRayMath} from '../Library/Math/WadRayMath.sol';
import {PercentageMath} from '../Library/Math/PercentageMath.sol';
import {IDToken} from '../Interface/IDToken.sol';
import {IKToken} from '../Interface/IKToken.sol';
import {ILendingPool} from '../Interface/ILendingPool.sol';
import {IPriceOracleGetter} from '../Interface/IPriceOracleGetter.sol';
import {IKSwapRouter} from '../Interface/IKSwapRouter.sol';
import {Errors} from '../Library/Helper/Errors.sol';
import {IERC20} from '../Dependency/openzeppelin/IERC20.sol';
import {Address} from '../Dependency/openzeppelin/Address.sol';
import {SafeMath} from '../Dependency/openzeppelin/SafeMath.sol';
import {SafeERC20} from '../Dependency/openzeppelin/SafeERC20.sol';
import {LendingPoolStorage} from './LendingPoolStorage.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {DataTypes} from '../Library/Type/DataTypes.sol';
import {GenericLogic} from '../Library/Logic/GenericLogic.sol';
import {LiquidationLogic} from '../Library/Logic/LiquidationLogic.sol';
import {MarginLogic} from '../Library/Logic/MarginLogic.sol';
import {MarketLogic} from '../Library/Logic/MarketLogic.sol';
import {ValidationLogic} from '../Library/Logic/ValidationLogic.sol';
import {ReserveLogic} from '../Library/Logic/ReserveLogic.sol';


contract LendingPool is ILendingPool, LendingPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using ReserveLogic for DataTypes.ReserveData;

  modifier whenNotPaused() {
    _whenNotPaused();
    _;
  }

  modifier whenPositionNotPaused() {
    _whenPositionNotPaused();
    _;
  }

  modifier onlyLendingPoolConfigurator() {
    _onlyLendingPoolConfigurator();
    _;
  }

  function _whenNotPaused() internal view {
    require(!_paused, Errors.GetError(Errors.Error.LP_IS_PAUSED));
  }

  function _whenPositionNotPaused() internal view {
    require(!_positionIsPaused, Errors.GetError(Errors.Error.LP_POSITION_IS_PAUSED));
  }

  function _onlyLendingPoolConfigurator() internal view {
    require(
      _addressesProvider.getLendingPoolConfigurator(address(this)) == msg.sender,
      Errors.GetError(Errors.Error.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR)
    );
  }

  constructor(
    ILendingPoolAddressesProvider provider,
    string memory poolName
  ) {
    _addressesProvider = provider;
    _maxNumberOfReserves = type(uint256).max; // unlimit reserve number at first
    _maximumLeverage = 20 * (10**27); // 20 ray
    _positionLiquidationThreshold = 2 * (10**25); // 0.02 ray
    _name = poolName;
  }

  /**
   * @dev Supply an `amount` of underlying asset into the reserve, receiving in return overlying kTokens.
   * - E.g. User supplies 100 USDC and gets in return 100 aUSDC
   * @param asset The address of the underlying asset to supply
   * @param amount The amount to be supplied
   * @param onBehalfOf The address that will receive the kTokens, same as msg.sender if the user
   *   wants to receive them on his own wallet, or a different address if the beneficiary of kTokens
   *   is a different wallet
   **/
  function supply(
    address asset,
    uint256 amount,
    address onBehalfOf
  ) external override whenNotPaused {
    MarketLogic.supply(
      MarketLogic.SupplyCallVars({
        asset: asset,
        amount: amount,
        onBehalfOf: onBehalfOf
      }),
      _reserves, 
      _usersConfig
    );
    _addUserToList(onBehalfOf);
  }

  /**
   * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent kTokens owned
   * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
   * @param asset The address of the underlying asset to withdraw
   * @param amount The underlying amount to be withdrawn
   *   - Send the value type(uint256).max in order to withdraw the whole kToken balance
   * @param to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a
   *   different wallet
   * @return The final amount withdrawn
   **/
  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external override whenNotPaused returns (uint256) {
    uint256 amountToWithdraw =
      MarketLogic.withdraw(
        MarketLogic.WithdrawCallVars({
          asset: asset,
          amount: amount,
          to: to,
          reservesCount: _reservesCount,
          oracleAddress: _addressesProvider.getPriceOracle()
        }),
        _reserves,
        _usersConfig,
        _reservesList
      );

    return amountToWithdraw;
  }

  /**
   * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
   * already supplied enough collateral, or he was given enough allowance by a credit delegator on the
   * corresponding debt token (dToken)
   * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
   *   and 100 dTokens, depending on the `interestRateMode`
   * @param asset The address of the underlying asset to borrow
   * @param amount The amount to be borrowed
   * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable (not valid), 2 for Variable
   * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
   * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
   * if he has been given credit delegation allowance
   **/
  function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    address onBehalfOf
  ) external override whenNotPaused {
    MarketLogic.borrow(
      MarketLogic.BorrowCallVars({
        asset: asset,
        user: msg.sender,
        onBehalfOf: onBehalfOf,
        amount: amount,
        interestRateMode: interestRateMode,
        releaseUnderlying: true,
        oracleAddress: _addressesProvider.getPriceOracle(),
        reservesCount: _reservesCount
      }),
      _reserves,
      _usersConfig,
      _reservesList
    );
  }

  /**
   * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
   * - E.g. User repays 100 USDC, burning 100 dTokens of the `onBehalfOf` address
   * @param asset The address of the borrowed underlying asset previously borrowed
   * @param amount The amount to repay
   * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
   * @param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
   * user calling the function if he wants to reduce/remove his own debt, or the address of any other
   * other borrower whose debt should be removed
   * @return The final amount repaid
   **/
  function repay(
    address asset,
    uint256 amount,
    uint256 rateMode,
    address onBehalfOf
  ) external override whenNotPaused returns (uint256) {
    uint256 paybackAmount =
      MarketLogic.repay(
        asset,
        amount,
        rateMode,
        onBehalfOf,
        _reserves,
        _usersConfig
      );
    return paybackAmount;
  }

  /**
   * @dev Allows supplyers to enable/disable a specific supplied asset as collateral
   * @param asset The address of the underlying asset supplied
   * @param useAsCollateral `true` if the user wants to use the supply as collateral, `false` otherwise
   **/
  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
    external
    override
    whenNotPaused
  {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    ValidationLogic.validateSetUseReserveAsCollateral(
      reserve,
      asset,
      useAsCollateral,
      _reserves,
      _usersConfig[msg.sender],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    _usersConfig[msg.sender].isUsingAsCollateral[reserve.id] = useAsCollateral;

    if (useAsCollateral) {
      emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
    } else {
      emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
    }
  }

  /**
   * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
   * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
   *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param user The address of the borrower getting liquidated
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param receiveAToken `true` if the liquidators wants to receive the collateral kTokens, `false` if he wants
   * to receive the underlying collateral asset directly
   **/
  function liquidationCall(
    address collateralAsset,
    address debtAsset,
    address user,
    uint256 debtToCover,
    bool receiveAToken
  ) external override whenNotPaused {
    (Errors.Error success, Errors.Error result) =
      LiquidationLogic.liquidationCall(
        LiquidationLogic.LiquidationCallCallVars({
          collateralAsset: collateralAsset,
          debtAsset: debtAsset,
          user: user,
          debtToCover: debtToCover,
          receiveAToken: receiveAToken,
          reservesCount: _reservesCount,
          oracleAddress: _addressesProvider.getPriceOracle()
        }),
        _reserves,
        _usersConfig,
        _reservesList
      );

    require(success == Errors.Error.CM_NO_ERROR, Errors.GetError(Errors.Error.LP_LIQUIDATION_CALL_FAILED));
    require(result == Errors.Error.LL_NO_ERRORS, Errors.GetError(result));
  }

  /**
   * @dev Returns the state and configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The state of the reserve
   **/
  function getReserveData(address asset)
    external
    view
    override
    returns (DataTypes.ReserveData memory)
  {
    return _reserves[asset];
  }

  /**
   * @dev Returns the user account data across all the reserves
   * @param user The address of the user
   * @return totalCollateralETH the total collateral in ETH of the user
   * @return totalDebtETH the total debt in ETH of the user
   * @return availableBorrowsETH the borrowing power left of the user
   * @return currentLiquidationThreshold the liquidation threshold of the user
   * @return ltv the loan to value of the user
   * @return healthFactor the current health factor of the user
   **/
  function getUserAccountData(address user)
    external
    view
    override
    returns (
      uint256 totalCollateralETH,
      uint256 totalDebtETH,
      uint256 availableBorrowsETH,
      uint256 currentLiquidationThreshold,
      uint256 ltv,
      uint256 healthFactor
    )
  {
    (
      totalCollateralETH,
      totalDebtETH,
      ltv,
      currentLiquidationThreshold,
      healthFactor
    ) = GenericLogic.calculateUserAccountData(
      user,
      _reserves,
      _usersConfig[user],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    availableBorrowsETH = GenericLogic.calculateAvailableBorrowsETH(
      totalCollateralETH,
      totalDebtETH,
      ltv
    );
  }

  /**
   * @dev Returns the configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The configuration of the reserve
   **/
  function getConfiguration(address asset)
    external
    view
    override
    returns (DataTypes.ReserveConfiguration memory)
  {
    return _reserves[asset].configuration;
  }

  function getPositionConfiguration(address asset)
    external
    view
    override
    returns (DataTypes.ReservePositionConfiguration memory)
  {
    return _reserves[asset].positionConfiguration;
  }

  /**
   * @dev Returns the configuration of the user across all the reserves
   * @param user The user address
   * @return The configuration of the user
   **/
  function getUserConfiguration(address user, uint id)
    external
    view
    override
    returns (bool, bool)
  {
    return (_usersConfig[user].isUsingAsCollateral[id], _usersConfig[user].isBorrowing[id]);
  }

  /**
   * @dev Returns the normalized income per unit of asset
   * @param asset The address of the underlying asset of the reserve
   * @return The reserve's normalized income
   */
  function getReserveNormalizedIncome(address asset)
    external
    view
    virtual
    override
    returns (uint256)
  {
    return _reserves[asset].getNormalizedIncome();
  }

  /**
   * @dev Returns the normalized variable debt per unit of asset
   * @param asset The address of the underlying asset of the reserve
   * @return The reserve normalized variable debt
   */
  function getReserveNormalizedDebt(address asset)
    external
    view
    override
    returns (uint256)
  {
    return _reserves[asset].getNormalizedDebt();
  }

  /**
   * @dev Returns if the LendingPool is paused
   */
  function paused() external view override returns (bool) {
    return _paused;
  }

  /**
   * @dev Returns the list of the initialized reserves
   **/
  function getReservesList() external view override returns (address[] memory) {
    address[] memory _activeReserves = new address[](_reservesCount);

    for (uint256 i = 0; i < _reservesCount; i++) {
      _activeReserves[i] = _reservesList[i];
    }
    return _activeReserves;
  }

  function getUsersList() external view override returns (address[] memory) {
    address[] memory _activeUsers = new address[](_usersCount);

    for (uint256 i = 0; i < _usersCount; i++) {
      _activeUsers[i] = _usersList[i];
    }
    return _activeUsers;
  }

  function getTradersList() external view override returns (address[] memory) {
    address[] memory _activeTraders = new address[](_tradersCount);

    for (uint256 i = 0; i < _tradersCount; i++) {
      _activeTraders[i] = _tradersList[i];
    }
    return _activeTraders;
  }

  /**
   * @dev Returns the cached LendingPoolAddressesProvider connected to this contract
   **/
  function getAddressesProvider() external view override returns (ILendingPoolAddressesProvider) {
    return _addressesProvider;
  }

  /**
   * @dev Returns the maximum number of reserves supported to be listed in this LendingPool
   */
  function MAX_NUMBER_RESERVES() external view returns (uint256) {
    return _maxNumberOfReserves;
  }

  /**
   * @dev Returns the position liquidation threshold in this lending pool (in ray)
   */
  function POSITION_LIQUIDATION_THRESHOLD() external view returns (uint256) {
    return _positionLiquidationThreshold;
  }

  /**
   * @dev Returns the maximum position leverage in this lending pool (in ray)
   */
  function MAX_LEVERAGE() external view returns (uint256) {
    return _maximumLeverage;
  }

  /**
   * @dev Validates and finalizes an kToken transfer
   * - Only callable by the overlying kToken of the `asset`
   * @param asset The address of the underlying asset of the kToken
   * @param from The user from which the kTokens are transferred
   * @param to The user receiving the kTokens
   * @param amount The amount being transferred/withdrawn
   * @param balanceFromBefore The kToken balance of the `from` user before the transfer
   * @param balanceToBefore The kToken balance of the `to` user before the transfer
   */
  function finalizeTransfer(
    address asset,
    address from,
    address to,
    uint256 amount,
    uint256 balanceFromBefore,
    uint256 balanceToBefore
  ) external override whenNotPaused {
    require(msg.sender == _reserves[asset].kTokenAddress, Errors.GetError(Errors.Error.LP_CALLER_MUST_BE_AN_ATOKEN));

    ValidationLogic.validateTransfer(
      from,
      _reserves,
      _usersConfig[from],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    uint256 reserveId = _reserves[asset].id;

    if (from != to) {
      if (balanceFromBefore.sub(amount) == 0) {
        DataTypes.UserConfigurationMap storage fromConfig = _usersConfig[from];
        fromConfig.isUsingAsCollateral[reserveId] = false;
        emit ReserveUsedAsCollateralDisabled(asset, from);
      }

      if (balanceToBefore == 0 && amount != 0) {
        DataTypes.UserConfigurationMap storage toConfig = _usersConfig[to];
        toConfig.isUsingAsCollateral[reserveId] = true;
        emit ReserveUsedAsCollateralEnabled(asset, to);
      }
    }
  }

  /**
   * @dev Initializes a reserve, activating it, assigning an kToken and debt tokens and an
   * interest rate strategy
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param kTokenAddress The address of the kToken that will be assigned to the reserve
   * @param dTokenAddress The address of the dToken that will be assigned to the reserve
   * @param interestRateStrategyAddress The address of the interest rate strategy contract
   **/
  function initReserve(
    address asset,
    address kTokenAddress,
    address dTokenAddress,
    address interestRateStrategyAddress
  ) external override onlyLendingPoolConfigurator {
    require(Address.isContract(asset), Errors.GetError(Errors.Error.LP_NOT_CONTRACT));
    _reserves[asset].init(
      kTokenAddress,
      dTokenAddress,
      interestRateStrategyAddress
    );
    _addReserveToList(asset);
  }

  /**
   * @dev Updates the address of the interest rate strategy contract
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param rateStrategyAddress The address of the interest rate strategy contract
   **/
  function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress)
    external
    override
    onlyLendingPoolConfigurator
  {
    _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
  }

  /**
   * @dev Sets the configuration bitmap of the reserve as a whole
   * - Only callable by the LendingPoolConfigurator contract
   * @param asset The address of the underlying asset of the reserve
   * @param configuration The new configuration bitmap
   **/
  function setConfiguration(address asset, DataTypes.ReserveConfiguration calldata configuration)
    external
    override
    onlyLendingPoolConfigurator
  {
    _reserves[asset].configuration = configuration;
  }

  function setPositionConfiguration(
    address asset,
    DataTypes.ReservePositionConfiguration calldata positionConfig
  )
    external
    override
    onlyLendingPoolConfigurator
  {
    _reserves[asset].positionConfiguration = positionConfig;
  }

  /**
   * @dev Set the _pause state of a reserve
   * - Only callable by the LendingPoolConfigurator contract
   * @param val `true` to pause the reserve, `false` to un-pause it
   */
  function setPause(bool val) external override onlyLendingPoolConfigurator {
    _paused = val;
    if (_paused) {
      emit Paused();
    } else {
      emit Unpaused();
    }
  }

  function _addReserveToList(address asset) internal {
    uint256 reservesCount = _reservesCount;

    require(reservesCount < _maxNumberOfReserves, Errors.GetError(Errors.Error.LP_NO_MORE_RESERVES_ALLOWED));

    bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

    if (!reserveAlreadyAdded) {
      _reserves[asset].id = reservesCount;
      _reservesList[reservesCount] = asset;

      _reservesCount = reservesCount + 1;
    }
  }

  function _addUserToList(address user) internal {
    bool userAlreadyAdded = _userActive[user] == true;

    if (!userAlreadyAdded) {
      _userActive[user] = true;
      _usersList[_usersCount] = user;

      _usersCount = _usersCount + 1;
    }
  }

  function _addTraderToList(address trader) internal {
    bool traderAlreadyAdded = _traderActive[trader] == true;

    if (!traderAlreadyAdded) {
      _traderActive[trader] = true;
      _tradersList[_usersCount] = trader;

      _tradersCount = _tradersCount + 1;
    }
  }

  /**
   * @dev Open a position, supply margin and borrow from pool. Traders should 
   * approve pools at first for the transfer of their assets
   * @param collateralAsset The address of asset the trader supply as margin
   * @param shortAsset The address of asset the trader would like to borrow at a leverage
   * @param longAsset The address of asset the pool will hold after swap
   * @param collateralAmount The amount of margin the trader transfers in margin decimals
   * @param leverage The leverage specified by user in ray
   **/
  function openPosition(
    address collateralAsset,
    address shortAsset,
    address longAsset,
    uint256 collateralAmount,
    uint256 leverage,
    uint256 minLongAmountOut,
    address onBehalfOf
  )
    external
    override
    whenNotPaused
    whenPositionNotPaused
    returns (
      DataTypes.TraderPosition memory position
    )
  {
    position = MarginLogic.openPosition(
      MarginLogic.OpenPositionCallVars({
        collateralAsset: collateralAsset,
        shortAsset: shortAsset,
        longAsset: longAsset,
        collateralAmount: collateralAmount,
        leverage: leverage,
        minLongAmountOut: minLongAmountOut,
        onBehalfOf: onBehalfOf,
        vaultAddress: address(this), // TODO: change to another vault
        maximumLeverage: _maximumLeverage,
        positionLiquidationThreshold: _positionLiquidationThreshold,
        positionsCount: _positionsCount,
        swapRouterAddress: _addressesProvider.getSwapRouter(),
        oracleAddress: _addressesProvider.getPriceOracle()
      }),
      _reserves
    );
    _addPositionToList(position);
    _addTraderToList(onBehalfOf);
  }

  /**
   * @dev Close a position, swap all margin / pnl into paymentAsset
   * @param positionId The id of position
   * @return paymentAmount The amount of asset to payback user 
   * @return pnl The pnl in ETH (wad)
   **/
  function closePosition(
    uint256 positionId,
    address to,
    uint256 minLongToShortAmountOut,
    uint256 minShortToCollateralAmountOut,
    uint256 minCollateralToShortAmountOut
  )
    external
    override
    whenNotPaused
    whenPositionNotPaused
    returns (
      uint256 paymentAmount,
      int256 pnl
    )
  {
    (paymentAmount, pnl) =
      MarginLogic.closePosition(
        MarginLogic.ClosePositionCallVars({
          id: positionId,
          to: to,
          vaultAddress: address(this),
          minLongToShortAmountOut: minLongToShortAmountOut,
          minShortToCollateralAmountOut: minShortToCollateralAmountOut,
          minCollateralToShortAmountOut: minCollateralToShortAmountOut,
          swapRouterAddress: _addressesProvider.getSwapRouter(),
          oracleAddress: _addressesProvider.getPriceOracle()
        }),
        _reserves,
        _usersConfig,
        _positionsList
      );
  }

  /**
   * @dev Close a position, swap all margin / pnl into paymentAsset
   * @param id The id of position
   **/
  function liquidationCallPosition(
    uint id
  )
    external
    override
    whenNotPaused
    whenPositionNotPaused
  {
    LiquidationLogic.liquidationCallPosition(
      LiquidationLogic.LiquidationCallPositionCallVars({
        id: id,
        oracleAddress: _addressesProvider.getPriceOracle()
      }),
      _reserves,
      _usersConfig,
      _positionsList
    );
  }

  function _addPositionToList(DataTypes.TraderPosition memory position) internal {
    _positionsList[_positionsCount] = position;
    _positionsList[_positionsCount].id = _positionsCount;
    _traderPositionMapping[position.traderAddress].push(position);

    _positionsCount = _positionsCount + 1;
  }

  function getTraderPositions(address trader) external view override returns (DataTypes.TraderPosition[] memory positions) {
    uint256 positionNumber = _traderPositionMapping[trader].length;
    positions = new DataTypes.TraderPosition[](positionNumber);
    for (uint i = 0; i < positionNumber; i++) {
      positions[i] = _traderPositionMapping[trader][i];
    }
  }

  function getPositionData(uint256 id) external view override returns (
    int256 pnl,
    uint256 healthFactor
  ) {
    DataTypes.TraderPosition storage position = _positionsList[id];
    pnl = GenericLogic.getPnL(position, _reserves, _addressesProvider.getPriceOracle());
    healthFactor = GenericLogic.calculatePositionHealthFactor(position, position.liquidationThreshold, _reserves, _addressesProvider.getPriceOracle());
  }

  function name() external view override returns (string memory) {
    return _name;
  }
}