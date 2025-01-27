const { ethers, upgrades } = require("hardhat");

async function main() {
    console.log("Deploying TokenFactoryUpgradeable...");

    const [deployer] = await ethers.getSigners()
    const weth = { address: "0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a" }

    const tokenImplementation = await deployContract("Token", [], "Token")

    const bondingCurve = await deployContract("BancorBondingCurve", [1000000, 1000000], "BondingCurve")

    let uniswapV3FactoryAddress = "0x12d21f5d0ab768c312e19653bf3f89917866b8e8";

    const PositionManager = new ContractFactory(nonfungiblePositionManager.abi, nonfungiblePositionManager.bytecode, deployer);
    const positionManager = await PositionManager.deploy(uniswapV3FactoryAddress, weth.address, ADDRESS_ZERO);

    const TokenFactoryUpgradeable = await ethers.getContractFactory("TokenFactoryUpgradeable");
    const proxy = await upgrades.deployProxy(
        TokenFactoryUpgradeable,
        [
            tokenImplementation.address, // _tokenImplementation,
            uniswapV3FactoryAddress,
            positionManager.address,
            bondingCurve.address, //_bondingCurve,
            weth.address,
            100, // _feePercent
        ],
        { initializer: "initialize" }
    );

    await proxy.deployed();

    console.log("TokenFactoryUpgradeable deployed to:", proxy.address);

    return { tokenFactory, bondingCurve };
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
