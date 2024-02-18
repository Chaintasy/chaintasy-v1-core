require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

module.exports = {
  solidity: {
    compilers: [
      {version: "0.8.15"}
    ] 
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  networks: {
    linea: {
      url: "https://rpc.goerli.linea.build/",
      accounts: [process.env.PRIVATE_KEY],
    },
    scrollAlpha: {
      url: "https://alpha-rpc.scroll.io/l2",
      accounts: [process.env.PRIVATE_KEY],
    },
    mumbai: {
      url: "https://polygon-mumbai.g.alchemy.com/v2/5FDX10WxboxRgKj3B6cS3qDF4Uixa5t1",
      accounts: [process.env.PRIVATE_KEY]
    },
    base: {
      url: "https://goerli.base.org",
      accounts: [process.env.PRIVATE_KEY],
    },
    arbitrumGoerli: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      accounts: [process.env.PRIVATE_KEY], 
    },
    sepolia: {
      url: "https://sepolia.gateway.tenderly.co",
      accounts: [process.env.PRIVATE_KEY],
    },
    optimismGoerli: {
      url: "https://optimism-goerli.public.blastapi.io",
      accounts: [process.env.PRIVATE_KEY],
    },
    scrollSepolia: {
      url: "https://sepolia-rpc.scroll.io/",
      accounts: [process.env.PRIVATE_KEY],
    },
    mantleTestnet: {
      url: "https://rpc.testnet.mantle.xyz",
      accounts: [process.env.PRIVATE_KEY],
    },
    scrollMainnet: {
      url: "https://rpc.scroll.io",
      accounts: [process.env.PRIVATE_KEY],
    },
    polygon: {
      url: "https://polygon-rpc.com/",
      accounts: [process.env.PRIVATE_KEY],
    },
    // for mainnet
   "blast-mainnet": {
    url: "coming end of February",
    accounts: [process.env.PRIVATE_KEY],
    gasPrice: 1000000000,
  },
  // for Sepolia testnet
  "blast-sepolia": {
    url: "https://sepolia.blast.io",
    accounts: [process.env.PRIVATE_KEY],
    gasPrice: 1000000000,
  },
  },
  // networks: {
  //   scrollTestnet: {
  //     url: process.env.SCROLL_TESTNET_URL || "",
  //     accounts:
  //       process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
  //   },
  // },
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