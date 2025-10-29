// 可编程NFT合约
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract NFTManager is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using Strings for uint256;

    // ============== Storage =====================
    uint256 public nextTokenId = 1;
    uint256 public maxSupply; // 最大供应量
    string public baseURI; // 基础URI
    address public editer;

    // Master/Print edition
    mapping(uint256 => bool) public isMaster;
    mapping(uint256 => uint256) public printEditionNumber; // Print edition 编号
    mapping(uint256 => uint256) public remainingUses; // 剩余核销次数
    mapping(uint256 => mapping(uint256 => bool)) public isPrintExist; // masterId => printNumber => exists, 用于防止重复铸造print edition
    mapping(uint256 => uint256) public fromMaster; // Print edition 来源的 Master ID
    mapping(address => mapping(uint256 => bool)) public isWhiteListed; // 白名单地址---允许铸造权限
    mapping(address => mapping(uint256 => bool)) public isEditer; // 核销权限地址

    // Metadata
    struct NFTMetadata {
        string name;
        string description;
        string image; // 图片 URL
        uint96 royaltyBps; // 版税，单位 BP（500 = 5%）
        address royaltyReceiver; // 版税收款地址
        uint256 usageLimit; // 可使用次数
    }
    mapping(uint256 => NFTMetadata) public metadata;

    // 转移控制
    mapping(uint256 => bool) public transferLocked;

    // ============== Events =====================
    event Received(address indexed sender, uint256 amount);
    event MintedNFT(
        address indexed to,
        uint256 tokenId,
        uint256 masterId,
        uint256 printNumber,
        uint256 usageLimit
    );
    event NFTUsed(uint256 tokenID, uint256 remainingUses, uint256 timestamp);

    // ============== Modifiers =====================
    modifier onlyWhiteListed(uint256 masterId) {
        require(
            isWhiteListed[msg.sender][masterId] || msg.sender == owner(),
            "Not whitelisted"
        );
        _;
    }

    modifier onlyEditer(uint256 tokenId) {
        _onlyEditer(tokenId);
        _;
    }

    function _onlyEditer(uint256 tokenId) internal view {
        uint256 _masterId = fromMaster[tokenId];
        require(
            isEditer[msg.sender][_masterId] || msg.sender == owner(),
            "No Access to eidt"
        );
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseURI_,
        address _initialOwner
    ) public initializer {
        maxSupply = maxSupply_;
        baseURI = baseURI_;
        __ERC721_init(name_, symbol_);

        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        _transferOwnership(_initialOwner);
        __Pausable_init();
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // // ===================== Mint =====================
    // function mint(address to) public onlyWhiteListed whenNotPaused {
    //     require(nextTokenId <= maxSupply, "Exceeds max supply");
    //     _safeMint(to, nextTokenId);
    //     nextTokenId++;
    // }

    // function mintBatch(
    //     address to,
    //     uint256 amount
    // ) public onlyWhiteListed whenNotPaused {
    //     require(nextTokenId + amount - 1 <= maxSupply, "Exceeds max supply");
    //     for (uint256 i = 0; i < amount; i++) {
    //         _safeMint(to, nextTokenId);
    //         nextTokenId++;
    //     }
    // }

    // ======================= Mint Master & Print Edition =====================

    function mintMaster(
        address to,
        NFTMetadata memory md
    ) external onlyWhiteListed(nextTokenId) whenNotPaused returns (uint256) {
        uint256 tokenId = nextTokenId++;
        _safeMint(to, tokenId);
        isMaster[tokenId] = true;
        metadata[tokenId] = md;

        remainingUses[tokenId] = md.usageLimit; // 初始化剩余使用次数

        emit MintedNFT(to, tokenId, tokenId, 0, md.usageLimit);
        return tokenId;
    }

    function mintPrintEdition(
        address to,
        uint256 masterId,
        uint256 printNumber
    ) external onlyWhiteListed(masterId) whenNotPaused returns (uint256) {
        require(nextTokenId <= maxSupply, "Exceeds max supply");
        require(isMaster[masterId], "Invalid masterId");
        require(
            !isPrintExist[masterId][printNumber],
            "Print number already exists"
        );

        uint256 tokenId = nextTokenId++;

        _safeMint(to, tokenId);

        // 标记为非 Master
        isMaster[tokenId] = false;
        fromMaster[tokenId] = masterId;

        // 设置 Print edition 编号
        printEditionNumber[tokenId] = printNumber;

        // 继承 Master 的 metadata
        metadata[tokenId] = metadata[masterId];
        isPrintExist[masterId][printNumber] = true;

        remainingUses[tokenId] = metadata[masterId].usageLimit;

        emit MintedNFT(
            to,
            tokenId,
            masterId,
            printNumber,
            metadata[tokenId].usageLimit
        );
        return tokenId;
    }

    function mintBatchPrintEditionByOrder(
        address to,
        uint256 amount,
        uint256 masterId,
        uint256 startingPrintNumber
    ) external onlyWhiteListed(masterId) whenNotPaused {
        require(nextTokenId + amount - 1 <= maxSupply, "Exceeds max supply");
        require(isMaster[masterId], "Invalid masterId");
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = nextTokenId++;

            _safeMint(to, tokenId);
            // 标记为非 Master
            isMaster[tokenId] = false;
            fromMaster[tokenId] = masterId;

            // Print edition 编号从 startingPrintNumber 开始
            while (!isPrintExist[masterId][startingPrintNumber]) {
                startingPrintNumber = startingPrintNumber + 1;
            }

            printEditionNumber[tokenId] = startingPrintNumber;
            isPrintExist[masterId][startingPrintNumber] = true;

            // 继承 Master 的 metadata
            metadata[tokenId] = metadata[masterId];
            remainingUses[tokenId] = metadata[masterId].usageLimit;

            emit MintedNFT(
                to,
                tokenId,
                masterId,
                startingPrintNumber,
                remainingUses[tokenId]
            );
        }
    }

    function mintBatchPrintEditionRandomMasters(
        address to,
        uint256[] calldata masterIds,
        uint256 totalAmount
    ) external whenNotPaused {
        for (uint256 i = 0; i < masterIds.length; i++) {
            require(isWhiteListed[msg.sender][masterIds[i]], "Not whitelisted");
        } // 检查 msg.sender 是否在所有masterId白名单内
        require(masterIds.length > 0, "No master IDs provided");
        require(
            nextTokenId + totalAmount - 1 <= maxSupply,
            "Exceeds max supply"
        );

        for (uint256 i = 0; i < totalAmount; i++) {
            // 随机选择一个 masterId
            uint256 randomIndex = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        i,
                        nextTokenId
                    )
                )
            ) % masterIds.length;

            uint256 masterId = masterIds[randomIndex];
            require(isMaster[masterId], "Invalid masterId");

            uint256 tokenId = nextTokenId++;

            _safeMint(to, tokenId);

            // 标记为非 Master
            isMaster[tokenId] = false;
            fromMaster[tokenId] = masterId;

            // 随机生成 print edition 编号，确保不重复
            uint256 startingPrintNumber = 1;
            while (isPrintExist[masterId][startingPrintNumber]) {
                startingPrintNumber++;
            }

            printEditionNumber[tokenId] = startingPrintNumber;
            isPrintExist[masterId][startingPrintNumber] = true;

            // 继承 Master 的 metadata
            metadata[tokenId] = metadata[masterId];
            remainingUses[tokenId] = metadata[masterId].usageLimit;

            emit MintedNFT(
                to,
                tokenId,
                masterId,
                startingPrintNumber,
                remainingUses[tokenId]
            );
        }
    }

    // function mintBatchPrintEditionRandom(
    //     address to,
    //     uint256 masterId,
    //     uint256[] memory printNumbers
    // ) public onlyWhiteListed whenNotPaused returns (uint256[] memory) {
    //     require(
    //         nextTokenId + printNumbers.length - 1 <= maxSupply,
    //         "Exceeds max supply"
    //     );
    //     require(isMaster[masterId], "Invalid masterId");
    //     uint256[] memory tokenIds = new uint256[](printNumbers.length);

    //     for (uint256 i = 0; i < printNumbers.length; i++) {
    //         uint256 tokenId = nextTokenId++;
    //         tokenIds[i] = tokenId;

    //         _safeMint(to, tokenId);
    //         // 标记为非 Master
    //         isMaster[tokenId] = false;
    //         fromMaster[tokenId] = masterId;

    //         // 设置 Print edition 编号
    //         require(
    //             !isPrintExist[masterId][printNumbers[i]],
    //             "Print number already exists"
    //         );
    //         printEditionNumber[tokenId] = printNumbers[i];
    //         isPrintExist[masterId][printNumbers[i]] = true;

    //         // 继承 Master 的 metadata
    //         metadata[tokenId] = metadata[masterId];

    //         remainingUses[tokenId] = metadata[masterId].usageLimit;
    //     }

    //     return tokenIds;
    // }

    // ===================== Metadata =====================
    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function tokenURL(
        uint256 tokenId
    ) public view virtual returns (string memory) {
        _requireOwned(tokenId);

        string memory basedURI = _baseURI();
        return
            bytes(basedURI).length > 0
                ? string.concat(baseURI, tokenId.toString(), ".json")
                : "";
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        _requireOwned(tokenId);

        NFTMetadata memory md = metadata[tokenId];

        // JSON metadata
        string memory json = string(
            abi.encodePacked(
                '{"name":"',
                md.name,
                '","description":"',
                md.description,
                '","image":"',
                md.image,
                '","attributes":[{"trait_type":"usageLimit","value":"',
                Strings.toString(md.usageLimit),
                '"}]}'
            )
        );

        // Base64 编码 JSON
        string memory jsonBase64 = Base64.encode(bytes(json));

        // 返回严格符合 ERC721 标准的 Data URI
        return
            string(
                abi.encodePacked("data:application/json;base64,", jsonBase64)
            );
    }

    // ===================== 版税（EIP-2981） =====================
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) public view returns (address receiver, uint256 royaltyAmount) {
        NFTMetadata memory md = metadata[tokenId];
        receiver = md.royaltyReceiver;
        if (receiver == address(0) || md.royaltyBps == 0) {
            return (address(0), 0);
        }
        // 计算版税金额
        royaltyAmount = (salePrice * md.royaltyBps) / 10000;
    }

    // ===================== 转移规则 =====================
    function lockTransfer(uint256 tokenId) external {
        _requireOwned(tokenId);
        require(
            msg.sender == owner() || msg.sender == ownerOf(tokenId),
            "Not authorized"
        );
        transferLocked[tokenId] = true;
    }

    function unlockTransfer(uint256 tokenId) external {
        _requireOwned(tokenId);
        require(
            msg.sender == owner() || msg.sender == ownerOf(tokenId),
            "Not authorized"
        );
        transferLocked[tokenId] = false;
    }

    // ====================== 核销使用次数, 必须tokenId的拥有者调用 =====================
    function useNFT(
        uint256 tokenId
    ) public nonReentrant onlyEditer(tokenId) whenNotPaused {
        _requireOwned(tokenId);
        require(remainingUses[tokenId] > 0, "No remaining uses");
        remainingUses[tokenId]--;

        // // 核销次数用完即销毁
        // if (remainingUses[tokenId] == 0) {
        //     burn(tokenId);
        // }
        emit NFTUsed(tokenId, remainingUses[tokenId], block.timestamp);
    }

    // ===================== 转移NFT =====================
    function TokenTransfer(address from, address to, uint256 tokenId) public {
        require(!transferLocked[tokenId], "Transfer locked for this NFT");
        safeTransferFrom(from, to, tokenId);
    }

    // ===================== 内部函数 =====================
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // function _exists(uint256 tokenId) internal view returns (bool) {
    //     address owner = _ownerOf(tokenId);
    //     if (owner == address(0)) {
    //         return false;
    //     }
    //     return true;
    // }

    // ============== 设置参数 =====================
    function setMaxSupply(uint256 maxSupply_) external onlyOwner {
        require(maxSupply_ >= nextTokenId - 1, "Cannot set less than minted");
        maxSupply = maxSupply_;
    }

    function setRoyaltyInfo(
        uint256 tokenId,
        address receiver,
        uint96 royaltyBps
    ) external {
        _requireOwned(tokenId);
        require(
            msg.sender == owner() || msg.sender == ownerOf(tokenId),
            "Not authorized"
        );
        require(receiver != address(0), "Invalid receiver");
        metadata[tokenId].royaltyReceiver = receiver;
        metadata[tokenId].royaltyBps = royaltyBps;
    }

    // ==================== white list =====================
    function setWhiteList(
        address operator,
        bool approved,
        uint256 masterId
    ) public onlyOwner {
        isWhiteListed[operator][masterId] = approved;
    }

    function setEditer(
        address operator,
        bool approved,
        uint256 masterId
    ) public onlyOwner {
        isEditer[operator][masterId] = approved;
    }

    // ===================== view functions =====================
    function getMetadata(
        uint256 tokenId
    ) external view returns (NFTMetadata memory) {
        _requireOwned(tokenId);
        return metadata[tokenId];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Override ERC721Upgradeable, IERC721
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721Upgradeable, IERC721) {
        require(!transferLocked[tokenId], "Transfer locked for this NFT");
        require(remainingUses[tokenId] > 0, "NFT has no remaining uses");

        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
        // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
        address previousOwner = _update(to, tokenId, _msgSender());
        if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    // ===================== 支持接口 =====================
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
