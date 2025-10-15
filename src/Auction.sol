// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";

import {NFTManager} from "./token/NFTManager.sol";

contract NFTAuction is
    ReentrancyGuardUpgradeable,
    ContextUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using LibTransferSafeUpgradeable for IERC721;
    using LibTransferSafeUpgradeable for address;

    uint256 public perFee; // 500 = 500 / 10000 = 5%

    struct Auction {
        address seller;
        address nftCollection;
        uint256 tokenId;
        address currency; // 竞价货币地址，ETH 用 address(0)
        uint256 minBid; // 起拍价
        uint256 endTime;
        bool settled;
        address highestBidder;
        uint256 highestBid;
    }

    struct Bid {
        address bidder;
        uint256 amount;
    }

    uint256 public auctionCount;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => uint256)) public pendingReturns;

    event AuctionCreated(
        uint256 auctionId,
        address seller,
        address nftCollection,
        uint256 tokenId,
        uint256 minBid,
        uint256 endTime,
        address currency
    );
    event LogWithdrawETH(address recipient, uint256 amount);
    event LogWithdrawERC20(address recipient, address token, uint256 amount);

    event BidPlaced(uint256 auctionId, address bidder, uint256 amount);
    event AuctionSettled(uint256 auctionId, address winner, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        uint256 _perFee
    ) public initializer {
        __Context_init();
        __Ownable_init(_initialOwner);
        perFee = _perFee;
    }

    // 创建拍卖
    function createAuction(
        address _nftCollection,
        uint256 _tokenId,
        address _currency,
        uint256 _minBid,
        uint256 _duration
    ) external nonReentrant whenNotPaused {
        require(_duration > 0, "Duration must be > 0");

        // 托管 NFT 到合约
        IERC721(_nftCollection).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );

        auctionCount++;
        auctions[auctionCount] = Auction({
            seller: msg.sender,
            nftCollection: _nftCollection,
            tokenId: _tokenId,
            currency: _currency,
            minBid: _minBid,
            endTime: block.timestamp + _duration,
            settled: false,
            highestBidder: address(0),
            highestBid: 0
        });

        emit AuctionCreated(
            auctionCount, // 拍卖编号
            msg.sender,
            _nftCollection,
            _tokenId,
            _minBid,
            block.timestamp + _duration,
            _currency
        );
    }

    // 参与拍卖
    function placeBid(
        uint256 _auctionId,
        uint256 _amount
    ) external payable nonReentrant whenNotPaused {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp < auction.endTime, "Auction ended");
        require(!auction.settled, "Auction settled");

        uint256 bidAmount;
        if (auction.currency == address(0)) {
            // ETH 出价
            bidAmount = msg.value;
        } else {
            // ERC20 出价
            IERC20 token = IERC20(auction.currency);
            require(
                token.transferFrom(msg.sender, address(this), _amount),
                "Transfer failed"
            );
            bidAmount = _amount;
        }

        require(bidAmount >= auction.minBid, "Bid below min price");
        require(bidAmount > auction.highestBid, "Bid not higher than current");

        // 返还上一次最高出价者
        if (auction.highestBid > 0) {
            pendingReturns[_auctionId][auction.highestBidder] += auction
                .highestBid;
        }

        auction.highestBid = bidAmount;
        auction.highestBidder = msg.sender;

        emit BidPlaced(_auctionId, msg.sender, bidAmount);
    }

    // 提现多余资金
    function withdraw(uint256 _auctionId) external nonReentrant whenNotPaused {
        uint256 amount = pendingReturns[_auctionId][msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingReturns[_auctionId][msg.sender] = 0;

        Auction storage auction = auctions[_auctionId];
        if (auction.currency == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(auction.currency).transfer(msg.sender, amount);
        }
    }

    // 拍卖结算
    function settleAuction(
        uint256 _auctionId
    ) external nonReentrant whenNotPaused {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp >= auction.endTime, "Auction not ended");
        require(!auction.settled, "Already settled");

        auction.settled = true;

        // 计算手续费
        uint256 auctionFee = (auction.highestBid * perFee) / 10000;
        // 计算版税
        (address royaltyReceiver, uint256 royaltyFee) = NFTManager(
            payable(auction.nftCollection)
        ).royaltyInfo(auction.tokenId, auction.highestBid);

        if (auction.highestBidder != address(0)) {
            // 赢家获得 NFT
            IERC721(auction.nftCollection).safeTransferFrom(
                address(this),
                auction.highestBidder,
                auction.tokenId
            );

            // 卖家收款(扣除手续费和版税)
            if (auction.currency == address(0)) {
                auction.seller.safeTransferETH(
                    auction.highestBid - auctionFee - royaltyFee
                );
                // 版税发送给创作者
                royaltyReceiver.safeTransferETH(royaltyFee);
            } else {
                IERC20(auction.currency).safeTransfer(
                    auction.seller,
                    auction.highestBid - auctionFee - royaltyFee
                );
                IERC20(auction.currency).safeTransfer(
                    royaltyReceiver,
                    royaltyFee
                );
            }
        } else {
            // 没有人出价，退回 NFT 给卖家
            IERC721(auction.nftCollection).safeTransferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
        }

        emit AuctionSettled(
            _auctionId,
            auction.highestBidder,
            auction.highestBid
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawETH(
        address recipient,
        uint256 amount
    ) external nonReentrant onlyOwner {
        recipient.safeTransferETH(amount);
        emit LogWithdrawETH(recipient, amount);
    }

    function withdrawERC20(
        address recipient,
        address token,
        uint256 amount
    ) external nonReentrant onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);
        emit LogWithdrawERC20(recipient, token, amount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}

    uint256[50] private __gap;
}
