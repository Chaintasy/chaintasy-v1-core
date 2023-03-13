// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BookManager.sol";

contract BidManager is Ownable {

    // Bid using the custom token
    IERC20 public CTY;

    // Winning bids will have the CTY token transferred to BookManager reward pools
    address public bookManager;

    address public bookLibrary;

    // Keep track of CTY balance in this contract
    uint256 public balanceOfBidderPool;

    // Bid amount will be unique value for each bid record
    address[] public booksWithBid;
    // Number of round => Book address => total bid amount
    mapping(uint16 => mapping(address => uint256)) public bookBidAmount;
    // Number of round => Book address => total bid amount
    mapping(uint16 => mapping(address => address[])) public bookBidders;
    // Number of round => Book address => bidder address => amount
    mapping(uint16 => mapping(address => mapping(address => uint256))) public bookBidderAmount;
    // Number of round => Book address => bidder address => disallow withdraw
    mapping(uint16 => mapping(address => mapping(address => bool))) public disallowWithdraw;

    // Bid end time, new value for each round of bidding
    uint256 public endTime;
    // Indicate if winning bids have been choosen
    bool public finalisedResult;
    // Minimum start bid amount
    uint256 public minBidAmount;
    // Indicate which round is the current bidding
    uint16 public numberOfRounds;
    // Keep track if winning bids for each round
    mapping(uint256 => address[]) public winingBidsRecord;

    event BidEvent(address bookAddress, uint256 amount);
    event WithdrawEvent(address bookAddress, uint256 amount);
    event FinaliseEvent(address[] result);

    constructor(){}

    // Update contract for future upgrade
    function updateBookManagerContract(address _contractAddress) public onlyOwner {
        bookManager = _contractAddress;
    }

    // Update contract for future upgrade
    function updateBookLibraryContract(address _contractAddress) public onlyOwner {
        bookLibrary = _contractAddress;
    }

    function updateCTYContract(address _ctyTokenAddress) public onlyOwner {
        CTY = IERC20(_ctyTokenAddress);
        CTY.approve(bookManager, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }  

    function updateMinBidAmount(uint256 _amount) public onlyOwner {
        minBidAmount = _amount;
    }   

    // Founder to kick start the bidding for each round
    function kickStartBiddingRound(uint256 _endTime) public onlyOwner {
        // Add in this check to avoid malicious act from owner;
        // require(endTime + 3 days > _endTime, "Unauthorise");
        endTime = _endTime;
        finalisedResult = false;
        numberOfRounds += 1;
    }

    // Bidders may bid once the round starts and before it ends
    // Each time bidder bids, it will add up the bid amount
    // Multiple bidders can bid for the same book to support the book
    function bid(address _bookAddress, uint256 _amount) public {
        require(block.timestamp < endTime, "Bidding has ended");
        require(_amount >= minBidAmount, "Less than min amount");
        BookLibrary bookLibraryContract = BookLibrary(bookLibrary);
        require(!bookLibraryContract.bookBlacklisted(_bookAddress), "Book Blacklisted");
 
        if (bookBidAmount[numberOfRounds][_bookAddress] == 0){
            booksWithBid.push(_bookAddress);
        }
        if (bookBidderAmount[numberOfRounds][_bookAddress][msg.sender] == 0){
            bookBidders[numberOfRounds][_bookAddress].push(msg.sender);
        }
        bookBidderAmount[numberOfRounds][_bookAddress][msg.sender] += _amount;
        bookBidAmount[numberOfRounds][_bookAddress] += _amount;
        balanceOfBidderPool += _amount;
        require(CTY.transferFrom(msg.sender, address(this), _amount), "Error in transfer");
        emit BidEvent(_bookAddress, bookBidderAmount[numberOfRounds][_bookAddress][msg.sender]);
    }

    // Bidders are free to withdraw their bid before the bidding round end time.
    // After the end time, bidders will need to wait for the founder to finalise the result.
    // Highest bidders will have 0 balance after finalising the result.
    // Remaining bidders may keep their bids for next round of bidding, or they can withdraw their bids
    // List of books with bids will be cleaned up when finalising result
    function withdrawBid(uint16 _numberOfRounds, address _bookAddress) public {
        require(!disallowWithdraw[_numberOfRounds][_bookAddress][msg.sender], "Your amount deducted for successful bidding");
        uint256 amount = bookBidderAmount[_numberOfRounds][_bookAddress][msg.sender];
        if (block.timestamp > endTime){
            require(finalisedResult, "Finalising result");
        }
        require(amount > 0, "Nothing to withdraw");
        require(balanceOfBidderPool >= amount, "Pool is empty");
        bookBidderAmount[_numberOfRounds][_bookAddress][msg.sender] = 0;
        bookBidAmount[_numberOfRounds][_bookAddress] -= amount;
        balanceOfBidderPool -= amount;

        // Update list of books with bid amount > 0
        if (bookBidAmount[_numberOfRounds][_bookAddress] == 0){
            for(uint256 i; i < booksWithBid.length; i++){
                if (booksWithBid[i] == _bookAddress){
                    booksWithBid[i] = booksWithBid[booksWithBid.length - 1];
                    booksWithBid.pop();
                    break;
                }
            }
        }

        // Update bidder list for the book
        uint256 length = bookBidders[_numberOfRounds][_bookAddress].length;
        for(uint256 i; i < length; i++){
            if (bookBidders[_numberOfRounds][_bookAddress][i] == msg.sender){
                bookBidders[_numberOfRounds][_bookAddress][i] = bookBidders[_numberOfRounds][_bookAddress][length-1];
                bookBidders[_numberOfRounds][_bookAddress].pop();
                break;
            }
        }

        require(CTY.transfer(msg.sender, amount), "Error in transfer");
        emit WithdrawEvent(_bookAddress, amount);
    }

    // Founder will prepare the list of highest bidder and upload to blockchain
    // The winning bidders' CTY will be transferred to BookManager contract reward pools
    // More percentage of the amount goes to the LikeRewardPool
    function finaliseBid(address[] memory _bookAddresses) public onlyOwner {
        require(!finalisedResult, "Result is finalised");
        require(block.timestamp > endTime, "Bidding in progress");
        require(_bookAddresses.length <= 9, "Max of 9 winning bids");

        for (uint8 i; i < _bookAddresses.length; i++){
            address tempBook = _bookAddresses[i];
            winingBidsRecord[numberOfRounds].push(tempBook);
            
            // Set all the bidders' amount for the book to 0
            for (uint8 j; j < bookBidders[numberOfRounds][tempBook].length; j++){
                disallowWithdraw[numberOfRounds][tempBook][bookBidders[numberOfRounds][tempBook][j]] = true;
            }

            uint256 bidAmount = bookBidAmount[numberOfRounds][tempBook];
            uint256 amount1 = bidAmount * 60 / 100;
            uint256 amount2 = bidAmount * 40 / 100;
            balanceOfBidderPool -= bidAmount;
            BookManager bookManagerContract = BookManager(bookManager);
            bookManagerContract.depositLikeRewardPool(amount1);
            bookManagerContract.depositRewardPool(amount2);
        }
        finalisedResult = true;
        emit FinaliseEvent(winingBidsRecord[numberOfRounds]);
    }

    function getWinningBidsRecord(uint256 _roundNumber) public view returns(address[] memory){
        return winingBidsRecord[_roundNumber];
    }

    function getBooksWithBid() public view returns(address[] memory){
        return booksWithBid;
    }

    function getBookBidders(uint8 _numberOfRounds, address _bookAddress) public view returns(address[] memory){
        return bookBidders[_numberOfRounds][_bookAddress];
    }
}