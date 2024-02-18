// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Book.sol";
import "./BookFactory.sol";
import "./BookLibrary.sol";
import "./BookMarketplace.sol";
import "./Membership.sol";
import "./IBlast.sol";

contract BookManager is Ownable {

    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
    
    IERC20 public CTY;

    // Pool of tokens accepted as chapter fee payment
    // 0 -> USDC, 1 -> USDT
    IERC20[] public stablecoinPool;

    // Pool of tokens accepted as tip payment
    // 0 -> CTY, 1 -> USDC, 2 -> USDT
    IERC20[] public tokenPool;

    // Keep track of CTY token balance
    // Depositer is guaranteed to get back the deposit amount
    uint256 public balanceOfDepositPool;

    // Reward pool gives out reward for depositing CTY for X days
    // Once depleted, no more reward for depositing
    uint256 public balanceOfRewardPool;

    // Like reward pool gives out reward for good content
    // Once depleted, no more reward for good content
    uint256 public balanceOfLikeRewardPool;

    // Store details when admin blacklists a book (by chapter)
    struct BlackListDetails {
        uint256 chapterId;
        string reason;
    }

    // Struct to track the details of the deposit
    struct DepositDetails {
        uint256 chapterId;
        uint256 amount;
        uint256 withdrawTime;
    }

    // Author Address => Book Address => chapter ID => deposit details
    mapping(address => mapping(address => mapping(uint256 => DepositDetails))) public depositRecords;

    address public bookFactoryAddress;
    address public bookLibraryAddress;
    address public bookMarketplaceAddress;
    address public membershipAddress;
    uint256 public REQUIRE_DEPOSIT_AMOUNT;
    uint256 public NUMBER_OF_LIKE_FOR_REWARD;
    uint256 public TIME_TO_WITHDRAW;

    event NewBook(address, string);
    event NewChapter(address, string);
    event WithdrawDeposit(address, string);
    event Deposit(address, string);
    event Payment(address, string);

    constructor() {
        BLAST.configureClaimableGas(); 

    }

    // Use Book Factory contract for upgradability of Book Contract
    function updateBookFactoryContract(address _bookFactory) public onlyOwner {
        bookFactoryAddress = _bookFactory;
    }

    // Add Book Library contract address
    function updateBookLibraryContract(address _bookLibrary) public onlyOwner {
        bookLibraryAddress = _bookLibrary;
    }

    // Add Book Marketplace contract address
    function updateBookMarketplaceContract(address _bookMarketplace) public onlyOwner {
        bookMarketplaceAddress = _bookMarketplace;
    }

    // Add Chaintasy Membership NFT contract address
    function updateMembershipContract(address _membership) public onlyOwner {
        membershipAddress = _membership;
    }

    // Add Chaintasy token address
    function updateCTYContract(address _ctyAddress) public onlyOwner {
        CTY = IERC20(_ctyAddress);
    }

    // Add stablecoin tokens to the pool 
    // Must be unique in the pool
    function addStablecoinToken(address _tokenAddress) public onlyOwner {
        for (uint8 i; i < stablecoinPool.length; i++) {
            require(
                stablecoinPool[i] != IERC20(_tokenAddress),
                "Already exist"
            );
        }
        stablecoinPool.push(IERC20(_tokenAddress));
    }

    // Add tokens to the tip pool
    // Must be unique in the pool
    function addToken(address _tokenAddress) public onlyOwner {
        for (uint8 i; i < tokenPool.length; i++) {
            require(tokenPool[i] != IERC20(_tokenAddress), "Already exist");
        }
        tokenPool.push(IERC20(_tokenAddress));
    }

    // Create new book 
    // Register the book address in Book Library contract
    function createNewBook(
        string memory _title,
        uint8 _category,
        string memory _image,
        string memory _description
    ) public {
        address book = BookFactory(bookFactoryAddress).newBook(
            msg.sender,
            membershipAddress,
            _title,
            _category,
            _image,
            _description
        );
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);
        bookLibrary.addBook(address(book), msg.sender);
        emit NewBook(msg.sender, "New Book Created");
    }

    // Add the deposit amount required for creating new chapter
    // Deposit token is only CTY 
    function updateRequireDepositAmount(uint256 _amount) public onlyOwner {
        REQUIRE_DEPOSIT_AMOUNT = _amount;
    }

    // Add the number of likes required to get the good content reward
    function updateNumberOfLikeForReward(uint256 _amount) public onlyOwner {
        NUMBER_OF_LIKE_FOR_REWARD = _amount;
    }

    // Add the time duration for deposit before withdrawal is allowed
    function updateTimeToWithdraw(uint256 _second) public onlyOwner {
        TIME_TO_WITHDRAW = _second;
    }

    // Pay the chapter fee in order to view the chapter content
    function pay(uint256 _pid, address _bookAddress, uint256 _tokenId, uint256 _amount) public {
        Book book = Book(_bookAddress);
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);
        require(_amount >= book.getFeeByChapter(_tokenId), "Insufficient fee");

        // Payment is with stablecoin
        require(_pid < stablecoinPool.length, "Invalid pool ID");
        IERC20 stablecoin = stablecoinPool[_pid];

        // 97.5% of the fee goes to author
        uint256 amountToAuthor = (_amount * 975) / 1000;
        // 2.5% if the fee goes to Chaintasy founder
        uint256 amountToFounder = (_amount * 25) / 1000;

        // Register the reader as having paid the chapter fee in Book contract
        book.updatePaidStatus(_tokenId, msg.sender);

        // Register the reader and amount in Book Library contract
        // This is for tracking who are the supporters of the book
        bookLibrary.addFeeAmount(
            _bookAddress,
            msg.sender,
            address(stablecoin),
            amountToAuthor
        );

        // Transfer the chapter fee to this contract
        require(
            stablecoin.transferFrom(msg.sender, address(this), _amount),
            "Payment failed"
        );

        // If owner has listed the chapter in Book Marketplace, to transfer chapter fee to the correct owner
        if (book.ownerOf(_tokenId) == bookMarketplaceAddress) {
            BookMarketplace bookMarketPlaceContract = BookMarketplace(bookMarketplaceAddress);
            require(
                stablecoin.transfer(
                    bookMarketPlaceContract.previousTokenOwner(_bookAddress, _tokenId),
                    amountToAuthor
                ),
                "Payment failed"
            );
        } else {
            require(
                stablecoin.transfer(book.ownerOf(_tokenId), amountToAuthor),
                "Payment failed"
            );
        }

        // Transfer 2.5% chapter fee to Chaintasy founder
        require(stablecoin.transfer(owner(), amountToFounder), "Payment failed");

        // Emit payment successful event
        emit Payment(msg.sender, "Payment successful");
    }

    // Allows any reader to support the author with tips
    function tip(uint256 _pid, address _bookAddress, uint256 _amount) public {
        Book book = Book(_bookAddress);
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);

        // Payment is with multi-token pool
        require(_pid < tokenPool.length, "Invalid pool ID");
        IERC20 token = tokenPool[_pid];

        // 97.5% of the fee goes to author
        uint256 amountToAuthor = (_amount * 975) / 1000;
        // 2.5% of the fee goes to Chaintasy founder
        uint256 amountToFounder = (_amount * 25) / 1000;

        // Register the reader and amount in Book Library contract
        // This is for tracking who are the supporters of the book
        bookLibrary.addTipAmount(
            _bookAddress,
            msg.sender,
            address(token),
            amountToAuthor
        );

        // Transfer the tip amount to this contract
        require(token.transferFrom(msg.sender, address(this), _amount), "Payment failed");
        
        // Transfer 97.5% of the tip amount to the author
        require(token.transfer(book.author(), amountToAuthor), "Payment failed");
        
        // Transfer 2.5% of the tip amount to Chaintasy founder
        require(token.transfer(owner(), amountToFounder), "Payment failed");
        
        // Emit tip successful event
        emit Payment(msg.sender, "Tip successful");
    }

    // Create new chapter
    function createNewChapter(
        address _bookAddress,
        uint256 _amount,
        string memory _chapterTitle,
        string memory _content,
        uint256 _fee
    ) public {
        Book book = Book(_bookAddress);
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);
        
        // Only the author is allowed to create new chapter
        require(book.author() == msg.sender, "Unauthorise");
        
        // Required to deposit CTY token for X days
        require(_amount >= REQUIRE_DEPOSIT_AMOUNT, "Insufficient token");

        // Required the book is not blacklisted by the admin
        require(
            !bookLibrary.bookBlacklisted(_bookAddress),
            "Book is blacklisted"
        );

        // mint new chapter NFT to the author
        book.mintChapter(msg.sender, _chapterTitle, _content, _fee);
        emit NewChapter(msg.sender, "New Chapter");

        // Register the new chapter to Book Library contract
        // *** Change this data to offchain ***
        // bookLibrary.addChapter(_bookAddress);

        // Create the deposit details for this transaction
        DepositDetails memory depositDetails = DepositDetails(
            book.tokenId(),
            _amount,
            block.timestamp + TIME_TO_WITHDRAW
        );

        // Create the deposit record bind to author address, book address and token ID
        depositRecords[msg.sender][_bookAddress][book.tokenId()] = depositDetails;
        
        // Increase the balance of the deposit pool of CTY tokens
        balanceOfDepositPool += _amount;

        // Transfer the CTY token to this address
        require(CTY.transferFrom(msg.sender, address(this), _amount), "Error in deposit");

        // Emit Deposit successful event
        emit Deposit(msg.sender, "Deposit successful");
    }

    // Withdraw deposit after X days
    function withdrawDeposit(address _bookAddress, uint256 _tokenId) public {
        DepositDetails memory depositDetails = depositRecords[msg.sender][_bookAddress][_tokenId];

        // Require current timestamp is past the withdrawal time 
        require(block.timestamp > depositDetails.withdrawTime,"Not the time yet");

        // Require the deposit amount to be more than 0
        // This will stop the author from repeated withdrawal 
        require(depositDetails.amount > 0, "Nothing to withdraw");

        // Calculate the like reward of 5%, if the like count exceeds the required number
        // If the like reward exceeds the like reward pool balance, no like reward will be given out
        uint256 likeReward = 0;
        uint256 likeCount = BookLibrary(bookLibraryAddress).chapterLikeCount(_bookAddress, _tokenId);
        if (likeCount >= NUMBER_OF_LIKE_FOR_REWARD) {
            likeReward = (depositDetails.amount * 500) / 10000;
            if (balanceOfLikeRewardPool < likeReward) {
                likeReward = balanceOfLikeRewardPool;
            }
        }

        // Compute the deposit reward of 3%
        // If the deposit reward exceeds the reward pool balance, no deposit reward will be given out
        uint256 depositReward = (depositDetails.amount * 300) / 10000;
        if (balanceOfRewardPool < depositReward) {
            depositReward = balanceOfRewardPool;
        }

        // Compute the total withdrawal amount, inclusive of the additional rewards
        uint256 totalWithdrawAmount = likeReward + depositReward + depositDetails.amount;

        // Update the balances of the CTY token
        balanceOfDepositPool -= depositDetails.amount;
        balanceOfRewardPool -= depositReward;
        balanceOfLikeRewardPool -= likeReward;

        // Reinitialize the deposit details such that author cannot withdraw multiple times
        delete (depositRecords[msg.sender][_bookAddress][_tokenId]);

        // Transfer the total withdrawal amount to the author
        require(CTY.transfer(msg.sender, totalWithdrawAmount), "Error in withdraw");
        
        // Emit withdrawal successful message
        emit WithdrawDeposit(msg.sender, "Withdraw successful");
    }

    // Penalise the author by taking away the deposit amount of a particular chapter
    // If the book was penalised for 3 times, Book Library contract will blacklist the book automatically
    function penalise(
        address _bookAddress,
        uint8 _tokenId,
        address _author,
        string memory _reason
    ) public onlyOwner {
        BookLibrary bookLibrary = BookLibrary(bookLibraryAddress);

        // Get the deposit details of the particular chapter
        DepositDetails memory depositDetails = depositRecords[_author][_bookAddress][_tokenId];

        // Book Library contract will place 1 warning on the book
        // Once the book has accumulated 3 warnings, the book will be blacklisted
        bookLibrary.penaliseBook(_bookAddress, _reason);

        // If deposit amount is more than 0,  
        // i.e. author has not withdraw the deposit or the duration is still within X days
        // 50% of the deposit amount will be confisticated and distributed to the reward pool and like reward pool
        // 50% of the deposit amount will be returned to the author
        if (depositDetails.amount > 0) {
            uint256 penaltyAmount = (depositDetails.amount * 50) / 100;
            uint256 returnAmount = (depositDetails.amount * 50) / 100;
            
            // Reinitialize the deposit details such that author cannot withdraw
            delete (depositRecords[_author][_bookAddress][_tokenId]);

            balanceOfDepositPool -= depositDetails.amount;
            balanceOfRewardPool += (penaltyAmount * 40) / 100;
            balanceOfLikeRewardPool += (penaltyAmount * 60) / 100;
            require(CTY.transfer(_author, returnAmount), "Error in transfer");
        }
    }

    // Allow external contract to deposit CTY to reward pool, e.g. Bid Manager contract
    function depositRewardPool(uint256 _amount) public {
        balanceOfRewardPool += _amount;
        require(CTY.transferFrom(msg.sender, address(this), _amount), "Error in deposit");
    }

    // Allow external contract to deposit CTY to like reward pool, e.g. Bid Manager contract
    function depositLikeRewardPool(uint256 _amount) public {
        balanceOfLikeRewardPool += _amount;
        require(CTY.transferFrom(msg.sender, address(this), _amount), "Error in deposit");
    }

    // Note: in production, you would likely want to restrict access to this
    function claimMyContractsGas() external onlyOwner{
        BLAST.claimMaxGas(address(this), msg.sender);
    }

}
