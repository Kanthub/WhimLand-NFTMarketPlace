// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "./utils/EmptyContract.sol";
import {EmptyContract} from "./utils/EmptyContract.sol";
import {NFTManager} from "../src/token/NFTManager.sol";

contract DeployerCpChainBridge is Script {
    EmptyContract public emptyContract;
    ProxyAdmin public nftManagerProxyAdmin;
    NFTManager public nftManager;
    NFTManager public nftManagerImplementation;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        emptyContract = new EmptyContract();

        TransparentUpgradeableProxy proxyNftManager =
            new TransparentUpgradeableProxy(address(emptyContract), deployerAddress, "");
        nftManager = NFTManager(payable(address(proxyNftManager)));
        nftManagerImplementation = new NFTManager();
        nftManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyNftManager)));

        nftManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(nftManager)),
            address(nftManagerImplementation),
            abi.encodeWithSelector(NFTManager.initialize.selector, "ABC_NFT", "abC", 100, "https:abc", deployerAddress)
        );

        console.log("deploy proxyNftManager:", address(proxyNftManager));
    }

    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
