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
import {Errors} from '../Library/Helper/Errors.sol';
import {IERC20} from '../Dependency/openzeppelin/IERC20.sol';
import {Address} from '../Dependency/openzeppelin/Address.sol';
import {SafeMath} from '../Dependency/openzeppelin/SafeMath.sol';
import {SafeERC20} from '../Dependency/openzeppelin/SafeERC20.sol';
import {LendingPoolStorage} from './LendingPoolStorage.sol';
import {ILendingPoolAddressesProvider} from '../Interface/ILendingPoolAddressesProvider.sol';
import {DataTypes} from '../Library/Type/DataTypes.sol';
import {GenericLogic} from '../Library/Logic/GenericLogic.sol';
import {ValidationLogic} from '../Library/Logic/ValidationLogic.sol';
import {ReserveLogic} from '../Library/Logic/ReserveLogic.sol';
import {IKSwapRouter} from '../Interface/IKSwapRouter.sol';

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
   * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying kTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
   * @param asset The address of the underlying asset to deposit
   * @param amount The amount to be deposited
   * @param onBehalfOf The address that will receive the kTokens, same as msg.sender if the user
   *   wants to receive them on his own wallet, or a different address if the beneficiary of kTokens
   *   is a different wallet
   **/
  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf
  ) external override whenNotPaused {
    DataTypes.ReserveData storage reserve = _reserves[asset];

    ValidationLogic.validateDeposit(reserve, amount);

    address kToken = reserve.kTokenAddress;

    reserve.updateState();
    reserve.updateInterestRates(asset, kToken, amount, 0);

    // NOTE: reduce complexity for frontend, as they need only approve once
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(asset).safeTransfer(kToken, amount);

    bool isFirstDeposit = IKToken(kToken).mint(onBehalfOf, amount, reserve.liquidityIndex);

    if (isFirstDeposit) {
      _usersConfig[onBehalfOf].isUsingAsCollateral[reserve.id] = true;
      emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf);
    }

    _addUserToList(onBehalfOf);

    emit Deposit(asset, msg.sender, onBehalfOf, amount);
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
    DataTypes.ReserveData storage reserve = _reserves[asset];

    address kToken = reserve.kTokenAddress;

    uint256 userBalance = IKToken(kToken).balanceOf(msg.sender);

    uint256 amountToWithdraw = amount;

    if (amount == type(uint256).max) {
      amountToWithdraw = userBalance;
    }

    ValidationLogic.validateWithdraw(
      asset,
      amountToWithdraw,
      userBalance,
      _reserves,
      _usersConfig[msg.sender],
      _reservesList,
      _reservesCount,
      _addressesProvider.getPriceOracle()
    );

    reserve.updateState();

    reserve.updateInterestRates(asset, kToken, 0, amountToWithdraw);

    if (amountToWithdraw == userBalance) {
      _usersConfig[msg.sender].isUsingAsCollateral[reserve.id] = false;
      emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
    }

    // transfer asset operation is in this burn function
    IKToken(kToken).burn(msg.sender, to, amountToWithdraw, reserve.liquidityIndex);

    emit Withdraw(asset, msg.sender, to, amountToWithdraw);

    return amountToWithdraw;
  }

  /**
   * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
   * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
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
    DataTypes.ReserveData storage reserve = _reserves[asset];

    _executeBorrow(
      ExecuteBorrowParams(
        asset,
        msg.sender,
        onBehalfOf,
        amount,
        interestRateMode,
        true
      )
    );

    emit Borrow(
      asset,
      msg.sender,
      onBehalfOf,
      amount,
      interestRateMode,
      reserve.currentBorrowRate
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
    DataTypes.ReserveData storage reserve = _reserves[asset];

    uint256 variableDebt = IERC20(reserve.dTokenAddress).balanceOf(onBehalfOf);

    DataTypes.InterestRateMode interestRateMode = DataTypes.InterestRateMode(rateMode);

    ValidationLogic.validateRepay(
      reserve,
      amount,
      interestRateMode,
      onBehalfOf,
      variableDebt
    );

    uint256 paybackAmount = variableDebt;

    if (amount < paybackAmount) {
      paybackAmount = amount;
    }

    reserve.updateState();

    {
      IDToken(reserve.dTokenAddress).burn(
        onBehalfOf,
        paybackAmount,
        reserve.borrowIndex
      );
    }

    address kToken = reserve.kTokenAddress;
    reserve.updateInterestRates(asset, kToken, paybackAmount, 0);

    if (variableDebt.sub(paybackAmount) == 0) {
      _usersConfig[onBehalfOf].isBorrowing[reserve.id] = false;
    }

    IERC20(asset).safeTransferFrom(msg.sender, address(this), paybackAmount);
    IERC20(asset).safeTransfer(kToken, paybackAmount);

    IKToken(kToken).handleRepayment(msg.sender, paybackAmount);

    emit Repay(asset, onBehalfOf, msg.sender, paybackAmount);

    return paybackAmount;
  }

  /**
   * @dev Allows depositors to enable/disable a specific deposited asset as collateral
   * @param asset The address of the underlying asset deposited
   * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise
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
    require(user != address(this), Errors.GetError(Errors.Error.LP_LIQUIDATE_LP));
    address collateralManager = _addressesProvider.getLendingPoolCollateralManager(address(this));

    //solium-disable-next-line
    (bool success, bytes memory result) =
      collateralManager.delegatecall(
        abi.encodeWithSignature(
          'liquidationCall(address,address,address,uint256,bool)',
          collateralAsset,
          debtAsset,
          user,
          debtToCover,
          receiveAToken
        )
      );

    require(success, Errors.GetError(Errors.Error.LP_LIQUIDATION_CALL_FAILED));

    (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

    require(returnCode == 0, string(abi.encodePacked(returnMessage)));
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

  struct ExecuteBorrowParams {
    address asset;
    address user;
    address onBehalfOf;
    uint256 amount;
    uint256 interestRateMode;
    bool releaseUnderlying;
  }

  function _executeBorrow(ExecuteBorrowParams memory vars) internal {
    DataTypes.ReserveData storage reserve = _reserves[vars.asset];
    DataTypes.UserConfigurationMap storage userConfig = _usersConfig[vars.onBehalfOf];

    address oracle = _addressesProvider.getPriceOracle();

    uint256 amountInETH =
      IPriceOracleGetter(oracle).getAssetPrice(vars.asset).mul(vars.amount).div(
        10**reserve.configuration.decimals
      );

    ValidationLogic.validateBorrow(
      vars.asset,
      reserve,
      vars.onBehalfOf,
      vars.amount,
      amountInETH,
      vars.interestRateMode,
      _reserves,
      userConfig,
      _reservesList,
      _reservesCount,
      oracle
    );

    reserve.updateState();

    bool isFirstBorrowing = false;
    {
      isFirstBorrowing = IDToken(reserve.dTokenAddress).mint(
        vars.user,
        vars.onBehalfOf,
        vars.amount,
        reserve.borrowIndex
      );
    }

    if (isFirstBorrowing) {
      userConfig.isBorrowing[reserve.id] = true;
    }

    address kToken = reserve.kTokenAddress;

    reserve.updateInterestRates(
      vars.asset,
      kToken,
      0,
      vars.releaseUnderlying ? vars.amount : 0
    );

    if (vars.releaseUnderlying) {
      IKToken(kToken).transferUnderlyingTo(vars.user, vars.amount);
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
    uint256 leverage
  )
    external
    whenNotPaused
    whenPositionNotPaused
    returns (
      DataTypes.TraderPosition memory position
    )
  {
    require(shortAsset != longAsset, Errors.GetError(Errors.Error.LP_POSITION_INVALID));
    require((leverage < _maximumLeverage) && (leverage > 10**27), Errors.GetError(Errors.Error.LP_LEVERAGE_INVALID));

    DataTypes.ReserveData storage shortReserve = _reserves[shortAsset];

    uint256 supplyTokenAmount = collateralAmount.rayMul(leverage);
    uint256 amountToShort = GenericLogic.calculateAmountToShort(collateralAsset, shortAsset, supplyTokenAmount, _reserves, _addressesProvider.getPriceOracle());

    ValidationLogic.validateOpenPosition(_reserves[collateralAsset], shortReserve, _reserves[longAsset], collateralAmount, amountToShort);

    IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), collateralAmount);
    
    shortReserve.updateState();
    IDToken(shortReserve.dTokenAddress).mint(
        msg.sender,
        address(this),
        amountToShort,
        shortReserve.borrowIndex
      );

    shortReserve.updateInterestRates(
      shortAsset,
      shortReserve.kTokenAddress,
      0,
      amountToShort
    );

    // if this fails, means there is not enough balance
    IKToken(shortReserve.kTokenAddress).transferUnderlyingTo(address(this), amountToShort);

    // transfer short into long through dex
    // TODO: validate after swap
    // TODO: mock swap
    uint256 longAmount;
    {
      IKSwapRouter swapRouter = IKSwapRouter(_addressesProvider.getSwapRouter());
      IERC20(shortAsset).safeTransfer(address(swapRouter), amountToShort);
      (, longAmount) = swapRouter.SwapExactTokensForTokens(
        shortAsset,
        longAsset,
        amountToShort,
        address(this)
      );
    }

    position = DataTypes.TraderPosition(
      // the trader
      msg.sender,
      // the token as margin
      collateralAsset,
      // the token to borrow
      shortAsset,
      // the token held
      longAsset,
      // the amount of provided margin
      collateralAmount,
      // the amount of borrowed asset
      amountToShort,
      // the amount of held asset
      longAmount,
      // the liquidationThreshold at trade
      _positionLiquidationThreshold,
      // id of position
      _positionsCount,
      // position is open
      true
    );

    _addPositionToList(position);
    _addTraderToList(msg.sender);

    emit OpenPosition(
      // the trader
      msg.sender,
      // the token as margin
      collateralAsset,
      // the token to borrow
      shortAsset,
      // the amount of provided margin
      collateralAmount,
      // the amount of borrowed asset
      amountToShort,
      // the liquidationThreshold at trade
      _positionLiquidationThreshold,
      // id of position
      _positionsCount
    );
  }

  /**
   * @dev Close a position, swap all margin / pnl into paymentAsset
   * @param id The id of position
   * @return paymentAmount The amount of asset to payback user 
   * @return pnl The pnl in ETH (wad)
   **/
  function closePosition(
    uint256 id
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
    DataTypes.TraderPosition storage position = _positionsList[id];
    address shortTokenAddress = position.shortTokenAddress;
    ValidationLogic.validateClosePosition(msg.sender, position);

    pnl = GenericLogic.getPnL(position, _reserves, _addressesProvider.getPriceOracle());

    paymentAmount = _closePosition(position, msg.sender, address(this));

    emit ClosePosition(
      id,
      position.traderAddress,
      position.collateralTokenAddress,
      position.collateralAmount,
      shortTokenAddress,
      position.shortAmount
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
    DataTypes.TraderPosition storage position = _positionsList[id];

    ValidationLogic.validateLiquidationCallPosition(
        position,
        _reserves,
        _addressesProvider.getPriceOracle()
      );
    
    _liquidationCallPosition(position, msg.sender);

    emit LiquidationCallPosition(
      id,
      msg.sender,
      position.traderAddress,
      position.collateralTokenAddress,
      position.collateralAmount,
      position.shortTokenAddress,
      position.shortAmount
    );
    emit ClosePosition(
      id,
      position.traderAddress,
      position.collateralTokenAddress,
      position.collateralAmount,
      position.shortTokenAddress,
      position.shortAmount
    );
  }

  function _closePosition(
    DataTypes.TraderPosition storage position,
    address receiver,
    address pool
  ) internal returns (uint256 paymentAmount) {
    // swap the longAsset into shortAsset first, compensate using collateral if there are losses
    {
      uint256 returnShortAmount;
      IKSwapRouter swapRouter = IKSwapRouter(_addressesProvider.getSwapRouter());

      {
        IERC20(position.longTokenAddress).safeTransfer(address(swapRouter), position.longAmount);
        (, returnShortAmount) = swapRouter.SwapExactTokensForTokens(
          position.longTokenAddress,
          position.shortTokenAddress,
          position.longAmount,
          address(this)
        );
      }

      if (position.shortAmount <= returnShortAmount) {
        paymentAmount = 0;

        if (position.shortAmount < returnShortAmount) {
          IERC20(position.longTokenAddress)
            .safeTransfer(address(swapRouter), returnShortAmount.sub(position.shortAmount));
          (, paymentAmount) = swapRouter.SwapExactTokensForTokens(
            position.shortTokenAddress,
            position.collateralTokenAddress,
            returnShortAmount.sub(position.shortAmount),
            address(this)
          );
        }
        paymentAmount.add(position.collateralAmount);
      } else {
        IERC20(position.longTokenAddress)
            .safeTransfer(address(swapRouter), position.shortAmount.sub(returnShortAmount));
        (, uint256 collateralSpent) = swapRouter.SwapExactTokensForTokens(
            position.collateralTokenAddress,
            position.shortTokenAddress,
            position.shortAmount.sub(returnShortAmount),
            address(this)
          );
        paymentAmount = position.collateralAmount.sub(collateralSpent);
      }

    }
    // repay
    DataTypes.ReserveData storage shortReserve = _reserves[position.shortTokenAddress];

    uint256 paybackAmount = position.shortAmount;

    shortReserve.updateState();

    {
      IDToken(shortReserve.dTokenAddress).burn(
        pool,
        paybackAmount,
        shortReserve.borrowIndex
      );
    }
    {
      address kToken = shortReserve.kTokenAddress;
      shortReserve.updateInterestRates(position.shortTokenAddress, kToken, paybackAmount, 0);

      uint256 variableDebt = IERC20(position.shortTokenAddress).balanceOf(pool);
      if (variableDebt.sub(paybackAmount) == 0) {
        _usersConfig[pool].isBorrowing[shortReserve.id] = false;
      }

      IERC20(position.shortTokenAddress).safeTransfer(kToken, paybackAmount);

      IKToken(kToken).handleRepayment(pool, paybackAmount);
    }
    {
      _positionsList[position.id].isOpen = false;
      IERC20(position.collateralTokenAddress).safeTransfer(receiver, paymentAmount);
    }
  }

  function _liquidationCallPosition(
    DataTypes.TraderPosition storage position,
    address caller
  ) internal {
    // repay
    DataTypes.ReserveData storage shortReserve = _reserves[position.shortTokenAddress];

    shortReserve.updateState();
    IDToken(shortReserve.dTokenAddress).burn(
      address(this),
      position.shortAmount,
      shortReserve.borrowIndex
    );

    shortReserve.updateInterestRates(position.shortTokenAddress, shortReserve.kTokenAddress, position.shortAmount, 0);

    uint256 variableDebt = IERC20(position.shortTokenAddress).balanceOf(address(this));
    if (variableDebt.sub(position.shortAmount) == 0) {
      _usersConfig[address(this)].isBorrowing[shortReserve.id] = false;
    }

    IERC20(position.shortTokenAddress).safeTransferFrom(
      caller,
      shortReserve.kTokenAddress,
      position.shortAmount
    );
    IKToken(shortReserve.kTokenAddress).handleRepayment(address(this), position.shortAmount);

    _positionsList[position.id].isOpen = false;
    IERC20(position.longTokenAddress).safeTransfer(caller, position.longAmount);
    IERC20(position.collateralTokenAddress).safeTransfer(caller, position.collateralAmount);
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
