// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./token/NFTManager.sol";
import "./token/ERC20Manager.sol";

contract CollectionFactory is Initializable, OwnableUpgradeable {
    address[] public allCollections;

    event CollectionCreated(
        address collectionAddress,
        string name,
        string symbol
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    function createCollection(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        string memory baseURI
    ) external returns (address) {
        NFTManager newCol = new NFTManager();
        newCol.initialize(name, symbol, maxSupply, baseURI, msg.sender);
        allCollections.push(address(newCol));
        emit CollectionCreated(address(newCol), name, symbol);
        return address(newCol);
    }

    function createERC20(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner
    ) external returns (address) {
        ERC20Manager newToken = new ERC20Manager();
        newToken.initialize(name, symbol, initialSupply, owner);

        return address(newToken);
    }
}
