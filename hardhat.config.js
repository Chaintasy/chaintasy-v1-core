require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

module.exports = {
  solidity: {
    compilers: [
      {version: "0.8.17"}
    ] 
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 1
    }
  },
  // networks: {
  //   mumbai: {
  //     url: process.env.TESTNET_RPC,
  //     accounts: [process.env.PRIVATE_KEY]
  //   },
  // },
  // etherscan: {
  //   apiKey: process.env.POLYGONSCAN_API_KEY
  // }
};