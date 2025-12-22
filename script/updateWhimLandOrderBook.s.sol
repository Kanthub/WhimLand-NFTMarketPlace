// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "./utils/EmptyContract.sol";
import {WhimLandOrderBook} from "../src/WhimLandOrderBook.sol";

contract UpgradeNFTManager is Script {
    ProxyAdmin public whimProxyAdmin;
    address public constant WHIMLAND_PROXY_ADDRESS =
        0xEA9DA365a233Bc7B8cc93e56cce30488c62F483E;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_WHIM");
        vm.startBroadcast(privateKey);

        // Deploy the new version of the NFTManager contract
        WhimLandOrderBook newWhim = new WhimLandOrderBook();

        whimProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(WHIMLAND_PROXY_ADDRESS)
        );

        // Perform the upgrade
        whimProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(WHIMLAND_PROXY_ADDRESS)),
            address(newWhim),
            ""
        );
        console.log(
            "NFTManager upgraded successfully to new implementation:",
            address(newWhim)
        );

        vm.stopBroadcast();
    }

    function getProxyAdminAddress(
        address proxy
    ) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
