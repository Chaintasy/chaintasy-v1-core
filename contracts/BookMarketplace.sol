// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Book.sol";
import "./BookLibrary.sol";
import "./BookManager.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BookMarketplace is Ownable, ERC721Holder {
    using Counters for Counters.Counter;
    Counters.Counter private listingCounter;
    Counters.Counter private activeListingCounter;
    Counters.Counter private transactionCounter;

    // 0 -> WETH, 1 -> USDC, 2 -> USDT, 3 -> CTY
    // Currently also allows 99 -> Native Token, not registered in this pool
    IERC20[] public paymentTokenPool;

    address public bookLibraryAddress;

    // Featured will have the CTY token transferred to BookManager reward pools
    address public bookManager;

    // Track previous owner when listing book for sale
    // This is to ensure payment of the reading fee is sent to correct owner when book is listed
    mapping(address => mapping(uint256 => address)) public previousTokenOwner;

    struct BookListing {
        uint256 id;
        address bookAddress;
        address lister;
        uint16[] tokenIds;
        uint256 listPrice;
        uint8 paymentTokenId;
        // 0 -> Delisted, 1 -> Listed, 2 -> Sold
        uint8 status;
        uint256 listTimestamp;
    }

    struct Transaction {
        address bookAddress;
        address seller;
        address buyer;
        uint16[] tokenIds;
        uint256 salePrice;
        uint8 paymentTokenId;
        uint256 transactionTimestamp;
    }

    struct Featured {
        BookListing bookListing;
        uint256 featuredTimestamp;
    }

    mapping(uint256 => BookListing) public listings; 
    mapping(uint256 => Transaction) public transactions;
    Featured[5] public featuredListings;
    uint256 public featureFee;

    event List(address, string); 
    event Delist(address, string);
    event Sale(address, string);
    event FeatureListing(address, string);

    constructor () { }

    function updateBookLibraryContract(address _bookLibraryAddress) public onlyOwner {
        bookLibraryAddress = _bookLibraryAddress;
    }

    // Update contract for future upgrade
    // Approve BookManager to transfer CTY from this contract to allow
    // transfer of Featured fee to reward pool and like reward pool
    function updateBookManagerContract(address _contractAddress) public onlyOwner {
        bookManager = _contractAddress;
        IERC20 CTY = IERC20(paymentTokenPool[3]);
        CTY.approve(bookManager, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    function updateFeatureFee(uint256 _fee) public onlyOwner {
        featureFee = _fee;
    }

    // Allows chapter owner to list the book chapter for sale
    function listBookChaptersForSale(address _bookAddress, uint16[] memory _tokenIds, uint256 _listPrice, uint8 _paymentTokenId) public {
        require(_tokenIds.length > 0, "Nothing to be listed");
        // Required book is not blacklisted
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);
        require(!bookLibrary.bookBlacklisted(_bookAddress), "Book is blacklisted");

        // Required msg sender is the owner of at least a token
        Book book = Book(_bookAddress);
        require(book.balanceOf(msg.sender) > 0, "Did not own the book");
    
        // List all the book chapters owned and selected by msg.sender
        // Book Collection start with index 1
        uint16 index = 0;
        while (index < _tokenIds.length){
            require(book.ownerOf(_tokenIds[index]) == msg.sender, "Did not own the book");
            require(
                block.timestamp >= book.getChapter(_tokenIds[index]).chapterCreationTimestamp + 10 minutes , 
                "Listing not allow within 10 minutes"
            );
            book.safeTransferFrom(msg.sender, address(this), _tokenIds[index]);

            // Track the owner of the book chapter so that 
            // readers paying to view the chapter will pay to correct owner 
            // instead of to BookMarketplace contract
            previousTokenOwner[_bookAddress][_tokenIds[index]] = msg.sender;
            index++;
        }
        
        listings[listingCounter.current()] = BookListing(
                                                listingCounter.current(), _bookAddress, msg.sender, 
                                                _tokenIds, _listPrice, _paymentTokenId, 1, block.timestamp);
        listingCounter.increment();
        activeListingCounter.increment();

        emit List(_bookAddress, "Listed");
    }

    // Allows chapter owner to delist their listing
    function delistBookForSale(address _bookAddress, uint256 _listingCounter) public {
        require(listingCounter.current() >= _listingCounter, "Listing not found");
        require(listings[_listingCounter].status == 1, "Book already delisted or sold");
        
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);
        if (bookLibrary.bookBlacklisted(_bookAddress)){
            // Blacklisted book cannot be listed in Book Marketplace for sale. 
            // However, the book can be blacklisted after it is placed for sale at Book Marketplace.
            // This then allows admin to delist a blacklisted book
            require(listings[_listingCounter].lister == msg.sender || owner() == msg.sender, "Unauthorised");
        } else {
            require(listings[_listingCounter].lister == msg.sender, "Unauthorised");
        }

        listings[_listingCounter].status = 0;
        activeListingCounter.decrement();
        
        Book book = Book(_bookAddress);
        
        // Book Collection start with index 1
        uint16 index = 0;
        while (index < listings[_listingCounter].tokenIds.length){
            book.safeTransferFrom(address(this), msg.sender, listings[_listingCounter].tokenIds[index]);
            delete previousTokenOwner[_bookAddress][listings[_listingCounter].tokenIds[index]];
            index++;
        }
        
        emit Delist(_bookAddress, "Delisted");
    }

    // Execute the sale and purchase of chapter NFT
    function executeSale(address _bookAddress, uint256 _listingCounter, uint8 _paymentTokenId, uint256 _paymentAmount) public payable {
        Book book = Book(_bookAddress);
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);

        require(!bookLibrary.bookBlacklisted(_bookAddress), "Book is blacklisted");
        require(listings[_listingCounter].status == 1, "Listing is not active");
        require(listings[_listingCounter].paymentTokenId == _paymentTokenId, "Invalid payment token");

        // If ETH, check msg.value. Otherwise, check amount
        if (listings[_listingCounter].paymentTokenId == 99) {
            require(listings[_listingCounter].listPrice == msg.value, "Invalid amount");
        } else {
            require(listings[_listingCounter].listPrice == _paymentAmount, "Invalid amount");
        }

        // Mark listing status as 2 -> sold
        listings[_listingCounter].status = 2;
        activeListingCounter.decrement();
        
        // Add to Transactions mapping
        transactions[transactionCounter.current()] = Transaction(
                                                        _bookAddress, listings[_listingCounter].lister, 
                                                        msg.sender, listings[_listingCounter].tokenIds,
                                                        listings[_listingCounter].listPrice, listings[_listingCounter].paymentTokenId, 
                                                        block.timestamp);
        transactionCounter.increment();

        // Transfer the payment to lister. 2.5% fee to Chaintasy founder
        uint256 fee = 25 * listings[_listingCounter].listPrice / 1000;
        uint256 amountToSeller = 975 * listings[_listingCounter].listPrice / 1000;
        if (listings[_listingCounter].paymentTokenId == 99){
            payable(owner()).transfer(fee);
            payable(listings[_listingCounter].lister).transfer(amountToSeller);
        } else {
            IERC20 token = paymentTokenPool[listings[_listingCounter].paymentTokenId];
            token.transferFrom(msg.sender, owner(), fee);
            token.transferFrom(msg.sender, listings[_listingCounter].lister, amountToSeller);
        }

        // Transfer chapter NFT to buyer
        uint16 index = 0;
        while (index < listings[_listingCounter].tokenIds.length){
            book.safeTransferFrom(address(this), msg.sender, listings[_listingCounter].tokenIds[index]);
            delete previousTokenOwner[_bookAddress][listings[_listingCounter].tokenIds[index]];
            index++;
        }
        
        emit Sale(_bookAddress, "Sold");
    }

    // Get active listing by range specified in the parameter
    function getLatestActiveListingByRange(uint256 _startIndex, uint256 _endIndex) public view returns (BookListing[] memory){
        require(_startIndex <= _endIndex, "Invalid range");
        BookListing[] memory bookListingByRange = new BookListing[](_endIndex - _startIndex + 1);    

        // Listing counter starts from 0, hence current() == length    
        uint256 length = listingCounter.current();

        uint256 index = 0;
        uint256 counter1 = 0;
        uint256 counter2 = 0;

        while (index < length){
            // Get the active listing in reverse order, i.e. latest listing first
            if (listings[length - 1 - index].status == 1){
                if (counter1 >= _startIndex && counter1 < _endIndex){
                    bookListingByRange[counter2] = listings[length - 1 - index];
                    counter2++;
                }

                // exit loop if already got the required range
                if (counter1 == _endIndex){
                    break;
                }
                counter1++;
            }
            index++;
        }

        return bookListingByRange;
    }

    // Get the list of successful sale and purchase transaction based on the specified range
    function getLatestTransactionByRange(uint256 _startIndex, uint256 _endIndex) public view returns (Transaction[] memory){
        uint256 length = transactionCounter.current();
        // BookListing[] memory tempBookListing
        if (_endIndex > length - 1){
            _endIndex = length - 1;
        }

        require(_startIndex <= _endIndex, "Invalid range");

        Transaction[] memory transactionByRange = new Transaction[](_endIndex - _startIndex + 1);
        uint256 index = 0;
        uint256 i = length - _startIndex - 1;
        uint256 j = length - _endIndex - 1;

        // return the addresses in reverse order
        for (i; i > j; i-- ){
            transactionByRange[index] = transactions[i];
            index++;
        }
        transactionByRange[index] = transactions[j];
        return transactionByRange;
    }

    // Get the marketplace listing featured at the top 5 spots of marketplace
    function featureListing(uint256 _listingCounter, uint256 _amount) public {
        require(_listingCounter <= listingCounter.current(), "Invalid listing counter");
        require(_amount >= featureFee, "Insufficient fee");
        
        // Payment token is only CTY       
        IERC20 CTY = IERC20(paymentTokenPool[3]);

        // Maximum of 5 spots allowed
        uint8 index = 5;
        uint8 currentFeaturedCount = 0;
        bool foundIndex = false;
        while (index > 0){
            // Check if the listing is already being featured, 
            // by comparing the listing counter ID and the book address
            if (featuredListings[index - 1].featuredTimestamp > 0){
                require(
                    featuredListings[index -1].bookListing.id != listings[_listingCounter].id && 
                    featuredListings[index -1].bookListing.bookAddress != listings[_listingCounter].bookAddress,
                    "Listing already featured"
                );

                // In the meanwhile, check what is the latest featured index
                // If currently there are 3 out of the 5 spots occupied, the latest index is 2.
                // New feature spot will be added to index 3 onwards
                if (!foundIndex){
                     currentFeaturedCount = index - 1;
                     foundIndex = true;
                }
            }
            index--;
        }

        // If all the featured spots have been taken up, 
        // check if the earliest spot has already expired.
        // Each featured spot will last for 5 days
        if (currentFeaturedCount == 4){
            // Require the earliest spot to be expired such that it can be freed for new feature.
            require(featuredListings[0].featuredTimestamp + 5 days < block.timestamp, "Max featured");
            
            // Push the earliest feature spot to the front, 
            // Push the latest feature spot to the end
            uint8 index2 = 0;
            while (index2 < 4){
                featuredListings[index2] = featuredListings[index2 + 1]; 
                index2++;
            }
            featuredListings[index2] = Featured(listings[_listingCounter], block.timestamp);
        } else {
            if (foundIndex) {
                // Add the latest feature spot to the empty spot 
                featuredListings[currentFeaturedCount + 1] = Featured(listings[_listingCounter], block.timestamp);
            } else {
                // This is the first featured spot 
                featuredListings[0] = Featured(listings[_listingCounter], block.timestamp);
            }
            
        }

        // Transfer the payment to BookMarketplace contract
        require(CTY.transferFrom(msg.sender, address(this), _amount), "Error in transfer");

        // The payment token will be distribute to BookManager reward pool and like reward pool
        // in the ration of 40/60
        uint256 amount1 = _amount * 60 / 100;
        uint256 amount2 = _amount * 40 / 100;
        BookManager bookManagerContract = BookManager(bookManager);
        bookManagerContract.depositLikeRewardPool(amount1);
        bookManagerContract.depositRewardPool(amount2);
        emit FeatureListing(msg.sender, "Featured");
    }

    // Add the list of payment tokens for Sale and Purchase of chapter NFTs
    function addToken(address _tokenAddress) public onlyOwner {
        for (uint8 i; i < paymentTokenPool.length; i++){
            require(paymentTokenPool[i] != IERC20(_tokenAddress), "Already exist");
        }
        paymentTokenPool.push(IERC20(_tokenAddress));
    }

    function getListingLength() public view returns (uint256){
        return listingCounter.current();
    }

    function getTransactionLength() public view returns (uint256){
        return transactionCounter.current();
    }

    function getActiveListingLength() public view returns (uint256){
        return activeListingCounter.current();
    }
}