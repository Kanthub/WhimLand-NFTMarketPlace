const { ethers, upgrades } = require("hardhat");

const esDex_name = "EasySwapOrderBook";
const esDex_address = "0xXXXXXXXX"

const esVault_name = "EasySwapVault";
const esVault_address = "0xXXXXXXXX"

/**  * 2024/10/09 in sepolia testnet
 * esVault contract deployed to: 
     esVault ImplementationAddress: 
     esVault AdminAddress: 
   esDex contract deployed to: 
      esDex ImplementationAddress: 
      esDex AdminAddress: 
 */

//use this scrips to upgrade contract if have a network file by importing previous deployments, if not use 'updateUsePerpareUpgrade' scripts
async function main() {
    const [signer, owner] = await ethers.getSigners();
    console.log(signer.address, " : signer");

    // let esDex = await ethers.getContractFactory(esDex_name);
    // console.log(await upgrades.erc1967.getImplementationAddress(esDex_address), " getOldImplementationAddress")
    // console.log(await upgrades.erc1967.getAdminAddress(esDex_address), " getAdminAddress")

    // esDex = await upgrades.upgradeProxy(esDex_address, esDex);
    // esDex = await esDex.deployed();
    // console.log("esDex upgraded");
    // console.log(await upgrades.erc1967.getImplementationAddress(esDex_address), " getNewImplementationAddress")

    // esVault
    let esVault = await ethers.getContractFactory(esVault_name);
    console.log(await upgrades.erc1967.getImplementationAddress(esVault_address), " getOldImplementationAddress")
    console.log(await upgrades.erc1967.getAdminAddress(esVault_address), " getAdminAddress")
    
    esVault = await upgrades.upgradeProxy(esVault_address, esVault);
    esVault = await esVault.deployed();
    console.log("esVault upgraded");
    console.log(await upgrades.erc1967.getImplementationAddress(esVault_address), " getNewImplementationAddress")
}


main()
    // eslint-disable-next-line no-process-exit
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        // eslint-disable-next-line no-process-exit
        process.exit(1);
    });
