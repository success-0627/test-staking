require("@nomiclabs/hardhat-waffle");
require('@openzeppelin/hardhat-upgrades');
require('@openzeppelin/upgrades-core')

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1337
    },
    // ropsten: {
    //   url: `https://ropsten.infura.io/v3/your_infrkey`,
    //   accounts: ['your_privatekey'],
    //   gasMultiplier: 1.25
    // },
    // mainnet: {
    //   url: `https://mainnet.infura.io/v3/your_infrkey`,
    //   accounts: ['your_privatekey'],
    //   gasMultiplier: 1.25
    // }
  },
  solidity: "0.8.5",
};
