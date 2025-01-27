const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0xProxyAddress";

  console.log("Upgrading TokenFactoryUpgradeable...");

  const TokenFactoryUpgradeableV2 = await ethers.getContractFactory("TokenFactoryUpgradeableV2");
  const upgraded = await upgrades.upgradeProxy(proxyAddress, TokenFactoryUpgradeableV2);

  console.log("TokenFactoryUpgradeable upgraded. Proxy now points to:", upgraded.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
