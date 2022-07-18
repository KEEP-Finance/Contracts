// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { parseUnits, concat } = require("ethers/lib/utils");
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
  // 1. Get deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer address: ", deployer.address);

  // 2. deploy mock tokens: usdc, eth, matic
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  let USDC = await MockERC20.deploy("USDC", "USDC", 6);
  await USDC.deployed();
  let ETH = await MockERC20.deploy("ETH", "ETH", 18);
  await ETH.deployed();
  let MATIC = await MockERC20.deploy("MATIC", "MATIC", 18);
  await MATIC.deployed();
  console.log("USDC address: ", USDC.address);
  console.log("ETH address: ", ETH.address);
  console.log("MATIC address: ", MATIC.address);

  // 3. deploy mock rate oracle
  const MockOracle = await hre.ethers.getContractFactory("MockPriceOracleGetter");
  let oracle = await MockOracle.deploy();
  await oracle.deployed();
  // add rate
  await oracle.setAssetPrice(USDC.address, parseUnits("6", 14));
  await oracle.setAssetPrice(ETH.address, parseUnits("1", 18));
  await oracle.setAssetPrice(MATIC.address, parseUnits("1", 14));
  console.log("Oracle address: ", oracle.address);

  // TODO: 3.5. deploy swap
  const MockSwap = await hre.ethers.getContractFactory("MockSwap");
  let swapRouter = await MockSwap.deploy(oracle.address);
  await swapRouter.deployed();
  console.log("Swap Address: ", swapRouter.address);

  // 4. deploy address provider
  const LendingPoolAddressesProvider = await hre.ethers.getContractFactory("LendingPoolAddressesProvider");

  let address_provider = await LendingPoolAddressesProvider
    .deploy(deployer.address, deployer.address, oracle.address, swapRouter.address);
  await address_provider.deployed();
  console.log("Address provider address: ", address_provider.address);
  // get libraries
  const ReserveLogic = await hre.ethers.getContractFactory("ReserveLogic");
  const GenericLogic = await hre.ethers.getContractFactory("GenericLogic");
  let generic_logic = await GenericLogic.deploy();
  await generic_logic.deployed();
  const ValidationLogic = await hre.ethers.getContractFactory("ValidationLogic", {libraries: {GenericLogic: generic_logic.address}});
  let reserve_logic = await ReserveLogic.deploy();
  let validation_logic = await ValidationLogic.deploy();
  await reserve_logic.deployed();
  await validation_logic.deployed();
  
  let library = {libraries: {ReserveLogic: reserve_logic.address, ValidationLogic: validation_logic.address, GenericLogic: generic_logic.address}}

  // 5. deploy 2 lending pools: main and eth-usdc
  const LendingPool = await hre.ethers.getContractFactory("LendingPool", {libraries: {ReserveLogic: reserve_logic.address, ValidationLogic: validation_logic.address, GenericLogic: generic_logic.address}});
  let main_pool = await LendingPool.deploy(address_provider.address, 'main');
  let eth_usdc_pool = await LendingPool.deploy(address_provider.address, 'eth-usdc');
  await main_pool.deployed();
  await eth_usdc_pool.deployed();
  console.log("Main Pool Address: ", main_pool.address);
  console.log("ETH-USDC Pool Address: ", eth_usdc_pool.address);

  // 6. deploy rate strategies
  const DefaultReserveInterestRateStrategy = await hre.ethers.getContractFactory("DefaultReserveInterestRateStrategy");
  let optimal_rate = parseUnits("0.9", 27);
  let base_rate = parseUnits("0.01", 27);
  let slope_1 = parseUnits("0.1", 27);
  let slope_2 = parseUnits("1", 27);
  let usdc_rate_strategy = await DefaultReserveInterestRateStrategy.deploy(
    address_provider.address,
    optimal_rate,
    base_rate,
    slope_1,
    slope_2
  );
  let eth_rate_strategy = await DefaultReserveInterestRateStrategy.deploy(
    address_provider.address,
    optimal_rate,
    base_rate,
    slope_1,
    slope_2
  );
  let matic_rate_strategy = await DefaultReserveInterestRateStrategy.deploy(
    address_provider.address,
    optimal_rate,
    base_rate,
    slope_1,
    slope_2
  );
  await usdc_rate_strategy.deployed();
  await eth_rate_strategy.deployed();
  await matic_rate_strategy.deployed();
  console.log("USDC strategy address: ", usdc_rate_strategy.address);
  console.log("ETH strategy address: ", eth_rate_strategy.address);
  console.log("MATIC strategy address: ", matic_rate_strategy.address);

  // 7. deploy configurator
  const LendingPoolConfigurator = await hre.ethers.getContractFactory("LendingPoolConfigurator");
  let main_pool_configurator = await LendingPoolConfigurator.deploy(address_provider.address, main_pool.address);
  let eth_usdc_pool_configurator = await LendingPoolConfigurator.deploy(address_provider.address, eth_usdc_pool.address);
  await main_pool_configurator.deployed();
  await eth_usdc_pool_configurator.deployed();
  console.log("Main pool configurator address: ", main_pool_configurator.address);
  console.log("ETH-USDC pool configurator address: ", eth_usdc_pool_configurator.address);

  // 8. deploy collateral manager
  const LendingPoolCollateralManager = await hre.ethers.getContractFactory("LendingPoolCollateralManager");
  let main_pool_cm = await LendingPoolCollateralManager.deploy();
  let eth_usdc_pool_cm = await LendingPoolCollateralManager.deploy();
  await main_pool_cm.deployed();
  await eth_usdc_pool_cm.deployed();
  console.log("Main pool cm address: ", main_pool_cm.address);
  console.log("ETH-USDC pool cm address: ", eth_usdc_pool_cm.address);

  // 9. add 2 pools to address provider
  await address_provider.addPool(
    main_pool.address,
    main_pool_configurator.address,
    main_pool_cm.address
  );
  await address_provider.addPool(
    eth_usdc_pool.address,
    eth_usdc_pool_configurator.address,
    eth_usdc_pool_cm.address
  );
  console.log("Pools registered");

  // 10. init ETH, USDC, MATIC on main pool
  let eth_init_reserve_input = [
    "18",
    eth_rate_strategy.address,
    ETH.address,
    deployer.address,
    "kETH",
    "kETH",
    "18",
    "dETH",
    "dETH",
    "18"
  ];
  let usdc_init_reserve_input = [
    "6",
    usdc_rate_strategy.address,
    USDC.address,
    deployer.address,
    "kUSDC",
    "kUSDC",
    "6",
    "dUSDC",
    "dUSDC",
    "6"
  ];
  let matic_init_reserve_input = [
    "18",
    matic_rate_strategy.address,
    MATIC.address,
    deployer.address,
    "kMATIC",
    "kMATIC",
    "18",
    "dMATIC",
    "dMATIC",
    "18"
  ];
  await main_pool_configurator.initReserve(
    eth_init_reserve_input
  );
  await main_pool_configurator.initReserve(
    usdc_init_reserve_input
  );
  await main_pool_configurator.initReserve(
    matic_init_reserve_input
  );
  console.log("reserves initialized: main pool")
  await main_pool_configurator.configureReserveAsCollateral(
    ETH.address,
    6000, // ltv
    6500, // liquidation threshold
    10500 // bonus
  );
  await main_pool_configurator.configureReserveAsCollateral(
    USDC.address,
    8000, // ltv
    9000, // liquidation threshold
    10500 // bonus
  );
  await main_pool_configurator.configureReserveAsCollateral(
    MATIC.address,
    6000, // ltv
    6500, // liquidation threshold
    10500 // bonus
  );
  console.log("reserves as collateral: main pool")
  await main_pool_configurator.enableBorrowingOnReserve(ETH.address);
  await main_pool_configurator.enableBorrowingOnReserve(USDC.address);
  await main_pool_configurator.enableBorrowingOnReserve(MATIC.address);
  console.log("reserves borrowing: main pool")
  await main_pool_configurator.setReserveFactor(ETH.address, 2000);
  await main_pool_configurator.setReserveFactor(USDC.address, 2000);
  await main_pool_configurator.setReserveFactor(MATIC.address, 2000);
  console.log("reserve factor: main pool")

  // 11. init ETH, USDC on ETH-USDC pool
  await eth_usdc_pool_configurator.initReserve(
    eth_init_reserve_input
  );
  await eth_usdc_pool_configurator.initReserve(
    usdc_init_reserve_input
  );
  console.log("reserves initialized: eth-usdc pool")
  await eth_usdc_pool_configurator.configureReserveAsCollateral(
    ETH.address,
    8000, // ltv
    9000, // liquidation threshold
    10500 // bonus
  );
  await eth_usdc_pool_configurator.configureReserveAsCollateral(
    USDC.address,
    9000, // ltv
    9500, // liquidation threshold
    10500 // bonus
  );
  console.log("reserves as collateral: eth-usdc pool")
  await eth_usdc_pool_configurator.enableBorrowingOnReserve(ETH.address);
  await eth_usdc_pool_configurator.enableBorrowingOnReserve(USDC.address);
  console.log("reserves borrowing: eth-usdc pool")
  await eth_usdc_pool_configurator.setReserveFactor(ETH.address, 2000);
  await eth_usdc_pool_configurator.setReserveFactor(USDC.address, 2000);
  console.log("reserve factor: eth-usdc pool")
  console.log("reserve done")
  
  // 12. unpause the pool
  await main_pool_configurator.setPoolPause(false);
  await eth_usdc_pool_configurator.setPoolPause(false);
  console.log("pools activated")

  // 13. readers
  const DataProvider = await hre.ethers.getContractFactory("DataProvider");
  let data_provider = await DataProvider.deploy(address_provider.address);
  await data_provider.deployed();
  console.log("Data provider address: ", data_provider.address);

  // TEST ONLY
  await USDC.approve(main_pool.address, parseUnits("1", 50));
  await ETH.approve(main_pool.address, parseUnits("1", 50));
  await MATIC.approve(main_pool.address, parseUnits("1", 50));

  await main_pool.deposit(ETH.address, parseUnits("1", 20), deployer.address)
  await main_pool.setUserUseReserveAsCollateral(ETH.address, true)
  await main_pool.borrow(ETH.address, parseUnits("1", 18), 1, deployer.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
