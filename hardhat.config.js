require("@nomiclabs/hardhat-waffle");
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    localhost: {
        url: "http://0.0.0.0:8545"
    },
    // Mumbai: {
    //   url: "https://matic-mumbai.chainstacklabs.com",
    //   accounts: [`0x${PRIVATE_KEY}`],
    //   gasPrice: 8000000000, // default is 'auto' which breaks chains without the london hardfork
    // },
    // BscTestnet: {
    //   url: "https://data-seed-prebsc-1-s3.binance.org:8545",
    //   accounts: [`0x${PRIVATE_KEY}`]
    // },
    // Fuji: {
    //   url: "https://api.avax-test.network/ext/bc/C/rpc",
    //   accounts: [`0x${PRIVATE_KEY}`]
    // }
    // oasisTestnet: {
    //   // url: "https://testnet.emerald.oasis.dev/",
    //   // accounts: [`0x${PRIVATE_KEY}`]
    // },
    // OptimismTestnet: {
    //   url: "https://kovan.optimism.io/",
    //   accounts: [`0x${PRIVATE_KEY}`]
    // },
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.14",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100000,
          }
        }
      },
    ],
    overrides: {
      "contracts/Pool/LendingPoolConfigurator.sol": {
        version: "0.8.14", 
        settings: {
          optimizer: {
            enabled: true,
            runs: 500
          }
        }
      }
    }
  }
}