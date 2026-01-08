// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MxNFTAuction is 
    IERC721Receiver, 
    ReentrancyGuard,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable {

    uint8 private constant USD_DECIMALS = 8;

    enum PaymentType {
        ETH,
        ERC20
    }

    struct Auction {
        IERC721 nft;
        uint256 nftId;
        address payable seller;

        PaymentType paymentType;
        IERC20 paymentToken;       // 仅 ERC20 时有效

        uint256 endTime;
        uint256 startingPrice;
        address highestBidder;
        uint256 highestBid;
        uint256 highestBidInDollar;
        bool settled;
    }

    uint256 public auctionCount;
    mapping(uint256 => Auction) public auctions;

    // auctionId => bidder => refundable ETH
    mapping(uint256 => mapping(address => uint256)) public pendingReturns;

    mapping(PaymentType => address) public priceFeeds;

    /* ========== EVENTS ========== */

    event AuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        address nft,
        uint256 nftId,
        uint256 endTime
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    event Withdrawn(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    event AuctionSettled(
        uint256 indexed auctionId,
        address winner,
        uint256 price
    );

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
    }

    /* ========== AUCTION LOGIC ========== */

    function startAuction(
        address nft,
        uint256 nftId,
        PaymentType paymentType,
        address paymentToken, // ETH 时传 address(0)
        uint256 startingPrice,
        uint256 duration
    ) external returns (uint256) {
        require(duration >= 1 minutes, "duration too short");

        IERC721(nft).safeTransferFrom(msg.sender, address(this), nftId);

        uint256 auctionId = auctionCount++;

        auctions[auctionId] = Auction({
            nft: IERC721(nft),
            nftId: nftId,
            seller: payable(msg.sender),
            endTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBid: 0,
            highestBidInDollar: 0,
            paymentType: paymentType,
            paymentToken: IERC20(paymentToken),
            startingPrice: startingPrice,
            settled: false
        });

        emit AuctionStarted(
            auctionId,
            msg.sender,
            nft,
            nftId,
            block.timestamp + duration
        );

        return auctionId;
    }

    function bidETH(uint256 auctionId) external payable nonReentrant {
        Auction storage auction = auctions[auctionId];

        require(PaymentType.ETH == auction.paymentType, "not eth auction");
        require(block.timestamp < auction.endTime, "auction ended");
        require(
            auction.highestBid == 0
                ? msg.value >= auction.startingPrice
                : msg.value > auction.highestBid, 
            "bid too low"
        );

        if (auction.highestBidder != address(0)) {
            pendingReturns[auctionId][auction.highestBidder]
                += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        auction.highestBidInDollar = _toUsd(
            msg.value,
            18,
            getPriceInDollar(PaymentType.ETH),
            getPriceDecimals(PaymentType.ETH)
        );
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    function bidERC20(uint256 auctionId, uint256 amount) external nonReentrant {
        Auction storage auction = auctions[auctionId];

        require(PaymentType.ERC20 == auction.paymentType, "not erc20 auction");
        require(block.timestamp < auction.endTime, "auction ended");
        require(amount > auction.highestBid, "bid too low");

        // transfer ERC20 from bidder to contract
        require(
            auction.paymentToken.transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "erc20 transfer failed"
        );

        if (auction.highestBidder != address(0)) {
            pendingReturns[auctionId][auction.highestBidder]
                += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = amount;
        auction.highestBidInDollar = _toUsd(
            amount,
            IERC20Metadata(address(auction.paymentToken)).decimals(),
            getPriceInDollar(PaymentType.ERC20),
            getPriceDecimals(PaymentType.ERC20)
        );

        emit BidPlaced(auctionId, msg.sender, amount);  
    }

    function withdraw(uint256 auctionId) external nonReentrant {
        uint256 amount = pendingReturns[auctionId][msg.sender];
        require(amount > 0, "nothing to withdraw");

        pendingReturns[auctionId][msg.sender] = 0;
        Auction storage auction = auctions[auctionId];
        if(auction.paymentType == PaymentType.ETH){
            (bool ok, ) = msg.sender.call{value: amount}("");
            require(ok, "ETH transfer failed");
        }else{
            require(auction.paymentToken.transfer(msg.sender, amount), "ERC20 transfer failed");
        }

        emit Withdrawn(auctionId, msg.sender, amount);
    }

    function settle(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];

        require(block.timestamp >= auction.endTime, "auction not ended");
        require(!auction.settled, "already settled");

        auction.settled = true;

        if (auction.highestBidder != address(0)) {
            // winner exists
            auction.nft.safeTransferFrom(
                address(this),
                auction.highestBidder,
                auction.nftId
            );
            if(auction.paymentType == PaymentType.ETH){
                (bool ok, ) = auction.seller.call{value: auction.highestBid}("");
                require(ok, "seller payment failed");
            }else{
                require(
                    auction.paymentToken.transfer(auction.seller, auction.highestBid), 
                    "ERC20 transfer failed"
                );
            }
        } else {
            // no bids
            auction.nft.safeTransferFrom(
                address(this),
                auction.seller,
                auction.nftId
            );
        }

        emit AuctionSettled(
            auctionId,
            auction.highestBidder,
            auction.highestBid
        );
    }

    function getPriceInDollar(PaymentType paymentType) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(priceFeeds[paymentType]);
        (
            /* uint80 roundId */
            ,
            int256 answer,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return uint256(answer);
    }

    function getPriceDecimals(PaymentType paymentType) public view returns (uint8) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(priceFeeds[paymentType]);
        return dataFeed.decimals();
    }

    function _toUsd(uint256 amount, uint8 amountDecimals, uint256 price, uint8 priceDecimals)
        internal
        pure
        returns (uint256)
    {
        uint256 scale = 10 ** uint256(amountDecimals);
        uint256 usd = (amount * price) / scale;
        if (priceDecimals > USD_DECIMALS) {
            usd /= 10 ** uint256(priceDecimals - USD_DECIMALS);
        } else if (priceDecimals < USD_DECIMALS) {
            usd *= 10 ** uint256(USD_DECIMALS - priceDecimals);
        }
        return usd;
    }   

    function setPriceFeed(PaymentType t, address feed) external {
        priceFeeds[t] = feed;
    }

    /* ========== ERC721 RECEIVER ========== */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _authorizeUpgrade(address)
        internal
        override
        onlyOwner
    {}
}
