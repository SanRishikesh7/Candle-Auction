// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract CandleAuction {
    struct Auction {
        address payable auctioneer;
        uint256 start;
        uint256 end;
        bool ended;
        address highestBidderTillNow;
        uint256 highestBid;
        bool randomnessProcessed;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionIdCount;

    mapping(uint256 => mapping(address => uint256)) public bids;

    event AuctionCreated(uint256 indexed auctionId, address indexed auctioneer, uint256 end);
    event BidAmount(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event BidWithdrawn(uint256 indexed auctionId, address indexed bidder, uint256 amount);

    modifier onlyAuctioneer(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].auctioneer, "Only the auctioneer can perform this action");
        _;
    }

    modifier auctionOngoing(uint256 auctionId) {
        require(block.number <= auctions[auctionId].end, "Auction has already ended");
        _;
    }

    modifier auctionEnded(uint256 auctionId) {
        require(block.number > auctions[auctionId].end, "Auction is still ongoing");
        require(!auctions[auctionId].ended, "Auction has already ended");
        _;
    }

    function createAuction(uint256 duration) public {
        auctionIdCount++;
        uint256 end = block.number + duration;
        auctions[auctionIdCount] = Auction({
            auctioneer: payable(msg.sender),
            start: block.number,
            end: end,
            ended: false,
            highestBidderTillNow: address(0),
            highestBid: 0,
            randomnessProcessed: false
        });

        emit AuctionCreated(auctionIdCount, msg.sender, end);
    }

    function makeBid(uint256 auctionId) public payable auctionOngoing(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(msg.value > auction.highestBid, "Bid is not higher than the current highest bid");

        if (auction.highestBid != 0) {
            bids[auctionId][auction.highestBidderTillNow] += auction.highestBid;
        }

        auction.highestBidderTillNow = msg.sender;
        auction.highestBid = msg.value;

        emit BidAmount(auctionId, msg.sender, msg.value);
    }

    function returnPreviousBid(uint256 auctionId) public {
        uint256 amount = bids[auctionId][msg.sender];
        require(amount > 0, "No funds to withdraw");

        bids[auctionId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit BidWithdrawn(auctionId, msg.sender, amount);
    }

    function getWinner(uint256 auctionId) public auctionEnded(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(!auction.randomnessProcessed, "Randomness already processed");

        auction.ended = true;
        auction.randomnessProcessed = true;

        if (auction.highestBidderTillNow != address(0)) {
            auction.auctioneer.transfer(auction.highestBid);
        }

        emit AuctionEnded(auctionId, auction.highestBidderTillNow, auction.highestBid);
    }

    function getRandomWinner(uint256 auctionId) public auctionEnded(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(!auction.randomnessProcessed, "Randomness already processed");

        // Using block.timestamp and blockhash for randomness
        uint256 randomValue = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1)))) % auction.highestBid;
        auction.randomnessProcessed = true;

        if (randomValue % 2 == 0 && auction.highestBidderTillNow != address(0)) {
            auction.auctioneer.transfer(auction.highestBid);
            emit AuctionEnded(auctionId, auction.highestBidderTillNow, auction.highestBid);
        } else {
            auction.highestBidderTillNow = address(0);
            emit AuctionEnded(auctionId, address(0), 0);
        }
    }
}
