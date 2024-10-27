const { ethers, upgrades } = require("hardhat")

/**  * 2024/10/09 in sepolia testnet
 * esVault contract deployed to: 
     esVault ImplementationAddress: 
     esVault AdminAddress: 
   esDex contract deployed to: 
      esDex ImplementationAddress: 
      esDex AdminAddress: 
 */

async function main() {
  const [deployer] = await ethers.getSigners()
  console.log("deployer: ", deployer.address)

//   let esVault = await ethers.getContractFactory("EasySwapVault")
//   esVault = await upgrades.deployProxy(esVault, { initializer: 'initialize' });
//   await esVault.deployed()
//   console.log("esVault contract deployed to:", esVault.address)
//   console.log(await upgrades.erc1967.getImplementationAddress(esVault.address), " esVault getImplementationAddress")
//   console.log(await upgrades.erc1967.getAdminAddress(esVault.address), " esVault getAdminAddress")

//   newProtocolShare = 200;
//   newESVault = "";
//   EIP712Name = "EasySwapOrderBook";
//   EIP712Version = "1";
//   let esDex = await ethers.getContractFactory("EasySwapOrderBook")
//   esDex = await upgrades.deployProxy(esDex, [newProtocolShare, newESVault, EIP712Name, EIP712Version], { initializer: 'initialize' });
//   await esDex.deployed()
//   console.log("esDex contract deployed to:", esDex.address)
//   console.log(await upgrades.erc1967.getImplementationAddress(esDex.address), " esDex getImplementationAddress")
//   console.log(await upgrades.erc1967.getAdminAddress(esDex.address), " esDex getAdminAddress")

  // esDexAddress = ""
  // esVaultAddress = ""
  // const esVault = await (
  //   await ethers.getContractFactory("EasySwapVault")
  // ).attach(esVaultAddress)
  // tx = await esVault.setOrderBook(esDexAddress)
  // await tx.wait()
  // console.log("esVault setOrderBook tx:", tx.hash)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
