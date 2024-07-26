// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract CandleAuction is VRFConsumerBase {
    struct Auction {
        address payable auctioneer;
        uint256 startBlock;
        uint256 endBlock;
        bool ended;
        address highestBidder;
        uint256 highestBid;
        bytes32 requestId;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionCount;

    mapping(uint256 => mapping(address => uint256)) public bids;

    event AuctionCreated(uint256 indexed auctionId, address indexed auctioneer, uint256 endBlock);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event BidWithdrawn(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event RandomnessRequest(uint256 indexed auctionId, bytes32 requestId);
    event WinnerSelected(uint256 indexed auctionId, address indexed winner);

    bytes32 internal keyHash;
    uint256 internal fee;
    mapping(bytes32 => uint256) public requestIdToAuctionId;

    modifier onlyAuctioneer(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].auctioneer, "Only the auctioneer can perform this action");
        _;
    }

    modifier auctionOngoing(uint256 auctionId) {
        require(block.number <= auctions[auctionId].endBlock, "Auction has already ended");
        _;
    }

    modifier auctionEnded(uint256 auctionId) {
        require(block.number > auctions[auctionId].endBlock, "Auction is still ongoing");
        require(!auctions[auctionId].ended, "Auction has already ended");
        _;
    }

    constructor(
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee
    ) VRFConsumerBase(_vrfCoordinator, _linkToken) {
        keyHash = _keyHash;
        fee = _fee;
    }

    function createAuction(uint256 duration) public {
        auctionCount++;
        uint256 endBlock = block.number + duration;
        auctions[auctionCount] = Auction({
            auctioneer: payable(msg.sender),
            startBlock: block.number,
            endBlock: endBlock,
            ended: false,
            highestBidder: address(0),
            highestBid: 0,
            requestId: bytes32(0)
        });

        emit AuctionCreated(auctionCount, msg.sender, endBlock);
    }

    function placeBid(uint256 auctionId) public payable auctionOngoing(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(msg.value > auction.highestBid, "Bid is not higher than the current highest bid");

        if (auction.highestBid != 0) {
            bids[auctionId][auction.highestBidder] += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    function returnPreviousBid(uint256 auctionId) public {
        uint256 amount = bids[auctionId][msg.sender];
        require(amount > 0, "No funds to withdraw");

        bids[auctionId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit BidWithdrawn(auctionId, msg.sender, amount);
    }

    function endAuction(uint256 auctionId) public auctionEnded(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.requestId == bytes32(0), "Randomness already requested for this auction");

        auction.ended = true;
        bytes32 requestId = requestRandomness(keyHash, fee);
        auction.requestId = requestId;
        requestIdToAuctionId[requestId] = auctionId;

        emit RandomnessRequest(auctionId, requestId);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomNumber) internal override {
        uint256 auctionId = requestIdToAuctionId[requestId];
        Auction storage auction = auctions[auctionId];
        require(auction.ended, "Auction is not ended yet");

        auction.ended = true;
        address winner = auction.highestBidder;
        uint256 winningBid = auction.highestBid;

        if (randomNumber % 2 == 0) { // Simple randomness example
            auction.auctioneer.transfer(winningBid);
            emit WinnerSelected(auctionId, winner);
        }

        emit AuctionEnded(auctionId, winner, winningBid);
    }

    function returnPreviousBid(uint256 auctionId) private {
        uint256 previousBid = bids[auctionId][msg.sender];
        if (previousBid > 0) {
            bids[auctionId][msg.sender] = 0;
            payable(msg.sender).transfer(previousBid);
        }
    }
}
