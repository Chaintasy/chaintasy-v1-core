// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlast.sol";

contract BookLibrary is Ownable {
    
    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

    // BookManager address, for safeguarding transaction
    address public bookManager;

    // Keep a list of books created
    address[] public bookAddresses;

    // *** Change this data to offchain ***
    // Keep a list of books with new chapter
    // This list will be constantly cleaned up by founder
    // address[] public booksWithNewChapter;

    // *** Change this data to offchain ***
    // Keep a list of books by category
    // mapping(uint8 => address[]) public booksByCategory;

    // Book address => Viewer address => already favourite?
    mapping(address => mapping(address => bool)) public bookToViewerFavourite;
    // Viewer address => Book addresses[]
    mapping(address => address[]) public viewerFavourite;
    // Book address => favourite count
    mapping(address => uint256) public bookFavouriteCount;

    // Book address => total like count by book
    mapping(address => uint256) public bookLikeCount;
    // Book address => token id => like count
    mapping(address => mapping(uint256 => uint256)) public chapterLikeCount;
    // Book address => token id => viewer => boolean
    mapping(address => mapping(uint256 => mapping(address => bool)))
        public bookChapterToViewerLike;

    // Book address => counter => reason
    mapping(address => mapping(uint8 => string)) public bookPenaltyReason;
    // Track warning count for the book. On 3rd warning, blacklist the book
    mapping(address => uint8) public bookWarningCount;
    // Track list of blacklisted books
    address[] public blacklistBooks;
    // Track book is blacklisted
    mapping(address => bool) public bookBlacklisted;

    // Track list of reported books, clean up when penalise books
    address[] public reportedBooks;
    // Track viewer address who reported the book
    mapping(address => mapping(address => string)) public bookToReportedReason;
    // Track report book reason
    mapping(address => address[]) public bookReporters;
    // Track malicious reporter address
    mapping(address => bool) public barredReporter;

    // Book address => tipper addresses
    mapping(address => address[]) public tippers;
    // Book address => viewer address => tip amount
    mapping(address => mapping(address => uint256)) public tipByBookAndViewer;
    // Book address => token address => total tip amount
    mapping(address => mapping(address => uint256)) public tipByBook;

    // Book address => paid viewer addresses
    mapping(address => address[]) public paidViewers;
    // Book address => viewer address => fee amount
    mapping(address => mapping(address => uint256)) public feeByBookAndViewer;
    // Book address => stablecoin address => total fee amount
    mapping(address => mapping(address => uint256)) public feeByBook;

    // Author address => list of books
    mapping(address => address[]) public booksByAuthor;
    // Author address => author name
    mapping(address => string) public authorNameByAddress;
    // keccak256(abi.encodePacked(authorName)) for maintaining unique name
    mapping(bytes32 => bool) public uniqueAuthorNameCheck;

    event Favourite(address, string);
    event Like(address, string);
    event Report(address, string);
    event Register(address, string);

    constructor() {
        BLAST.configureClaimableGas();
    }

    function updateBookManagerContract(address _bookManager) public onlyOwner {
        bookManager = _bookManager;
    }

    // Add new books
    // Trigger only by BookManager contract during creation of new book
    function addBook(address _bookAddress, address _authorAddress) public {
        require(msg.sender == bookManager, "Unauthorise");
        bookAddresses.push(_bookAddress);
        booksByAuthor[_authorAddress].push(_bookAddress);
        // booksByCategory[_category].push(_bookAddress);
    }

    // Add book with new chapter to the array
    // Trigger only by BookManager contract during creation of new chapter
    // To consider moving this off-chain
    // *** Change this data to offchain ***
    // function addChapter(address _bookAddress) public {
    //     require(msg.sender == bookManager, "Unauthorise");
    //     booksWithNewChapter.push(_bookAddress);
    // }

    // For authors to register unique name to identify themselves
    // May consider to change to Soul-bound token
    function registerAuthorName(string memory _authorName) public {
        bytes memory tempAuthorName = bytes(authorNameByAddress[msg.sender]);
        require(tempAuthorName.length == 0, "Already registered");
        require(
            !uniqueAuthorNameCheck[keccak256(abi.encodePacked(_authorName))],
            "Name is taken"
        );
        uniqueAuthorNameCheck[keccak256(abi.encodePacked(_authorName))] = true;
        authorNameByAddress[msg.sender] = _authorName;
        emit Register(msg.sender, _authorName);
    }

    // For readers to report the book which violates the policy
    // Admin will follow up with assessment of the book
    function reportBook(address _bookAddress, string memory _reportReason) public {
        // Bar malicious readers for reporting arbitrarily 
        require(!barredReporter[msg.sender], "You are barred");

        // Each reader can only report the book once
        require(
            bytes(bookToReportedReason[_bookAddress][msg.sender]).length == 0,
            "You have already reported this book"
        );

        // If it is the first time the book is being reported,
        // add the book to reportedBooks array
        if (bookReporters[_bookAddress].length == 0) {
            reportedBooks.push(_bookAddress);
        }

        // Store the reason from the reader
        bookToReportedReason[_bookAddress][msg.sender] = _reportReason;

        // Store the reader address
        bookReporters[_bookAddress].push(msg.sender);

        // Emit Reported event
        emit Report(_bookAddress, _reportReason);
    }

    // Allows the admin to remove book from report list, 
    // e.g. due to malicious reader reporting arbitrarily
    // e.g. admin assesses the book does not violate the policy
    function removeReportedBook(address _bookAddress) public onlyOwner {
        // Delete the list of reporters
        delete bookReporters[_bookAddress];

        // Remove book from the reportedBooks array
        uint256 index = 0;
        while (index < reportedBooks.length) {
            if (reportedBooks[index] == _bookAddress) {
                reportedBooks[index] = reportedBooks[reportedBooks.length - 1];
                reportedBooks.pop();
                break;
            }
            index++;
        }
    }

    // Bar or unbar the reader from reporting books
    function updateReporterStatus(address _reporter, bool _status) public onlyOwner {
        barredReporter[_reporter] = _status;
    }

    // Place 1 warning count each time the book is penalised. 
    // On the third warning count, the book will be blacklisted automatically
    // Triggered from BookManager contract
    function penaliseBook(address _bookAddress, string memory _reason) public {
        // Only BookManager is allowed to trigger this
        require(msg.sender == bookManager, "Unauthorise");

        // Place 1 warning count
        bookWarningCount[_bookAddress] += 1;
        // Tracks the reason for each warning
        bookPenaltyReason[_bookAddress][bookWarningCount[_bookAddress]] = _reason;

        // On the third warning, the book is blacklisted
        if (bookWarningCount[_bookAddress] == 3) {
            blacklistBooks.push(_bookAddress);
            bookBlacklisted[_bookAddress] = true;

            /* Good-to-have requirement, depends on transaction fee */
            // Remove blacklisted book from bookAddresses list
            uint256 index = 0;
            while (index < bookAddresses.length) {
                if (bookAddresses[index] == _bookAddress) {
                    while (index + 1 < bookAddresses.length) {
                        bookAddresses[index] = bookAddresses[index + 1];
                        index++;
                    }
                    bookAddresses.pop();
                    break;
                }
                index++;
            }

            // *** Change this data to offchain ***
            /* Good-to-have requirement, depends on transaction fee */
            // Remove blacklisted book from booksByCategory list
            // index = 0;
            // while (index < booksByCategory[_category].length) {
            //     if (booksByCategory[_category][index] == _bookAddress) {
            //         while (index + 1 < booksByCategory[_category].length) {
            //             booksByCategory[_category][index] = booksByCategory[_category][index + 1];
            //             index++;
            //         }
            //         booksByCategory[_category].pop();
            //         break;
            //     }
            //     index++;
            // }
        }
    }

    // Due to appeals or mistakes from admin, book can be reinstated from blacklist
    function removeBlacklistBook(address _bookAddress) public onlyOwner {
        require(bookBlacklisted[_bookAddress], "Not blacklisted");

        // Reset the book status
        bookWarningCount[_bookAddress] = 0;
        bookBlacklisted[_bookAddress] = false;
        bookAddresses.push(_bookAddress);
        // booksByCategory[_category].push(_bookAddress);

        // Remove the book from blacklist array
        uint256 index = 0;
        while (index < blacklistBooks.length) {
            if (blacklistBooks[index] == _bookAddress) {
                blacklistBooks[index] = blacklistBooks[blacklistBooks.length - 1];
                blacklistBooks.pop();
                break;
            }
            index++;
        }
    }

    // To track the tip transactions and know who are the supporters of the author
    // Triggered from BookManager contract whenever readers tip the author
    function addTipAmount(address _bookAddress, address _viewer, address _token, uint256 _amount) public {
        require(msg.sender == bookManager, "Unauthorise");
        if (tipByBookAndViewer[_bookAddress][_viewer] == 0) {
            tippers[_bookAddress].push(_viewer);
        }
        tipByBookAndViewer[_bookAddress][_viewer] += _amount;
        tipByBook[_bookAddress][_token] += _amount;
    }

    // To track the pay to view transactions and know who are the supporters of the book
    // Triggered from BookManager contract whenever readers pay the chapter fee
    function addFeeAmount(address _bookAddress, address _viewer, address _stablecoin, uint256 _amount ) public {
        require(msg.sender == bookManager, "Unauthorise");
        if (feeByBookAndViewer[_bookAddress][_viewer] == 0) {
            paidViewers[_bookAddress].push(_viewer);
        }
        feeByBookAndViewer[_bookAddress][_viewer] += _amount;
        feeByBook[_bookAddress][_stablecoin] += _amount;
    }

    // To track the readers' favourite books
    function addFavouriteBook(address _bookAddress) public {
        require(
            !bookToViewerFavourite[_bookAddress][msg.sender],
            "Already favourite"
        );
        viewerFavourite[msg.sender].push(_bookAddress);
        bookFavouriteCount[_bookAddress] += 1;
        bookToViewerFavourite[_bookAddress][msg.sender] = true;
        emit Favourite(msg.sender, "Favourite");
    }

    // To allow the readers to unfavourite a book
    function removeFavourite(address _bookAddress) public {
        require(
            bookToViewerFavourite[_bookAddress][msg.sender],
            "Not favourite"
        );
        for (uint128 index = 0; index < viewerFavourite[msg.sender].length; index++) {
            if (viewerFavourite[msg.sender][index] == _bookAddress) {
                for (index; index < viewerFavourite[msg.sender].length - 1; index++) {
                    viewerFavourite[msg.sender][index] = viewerFavourite[msg.sender][index + 1];
                }
                viewerFavourite[msg.sender].pop();
                break;
            }
        }
        bookFavouriteCount[_bookAddress] -= 1;
        bookToViewerFavourite[_bookAddress][msg.sender] = false;
        emit Favourite(msg.sender, "Unfavourite");
    }

    // To allow readers to like a chapter of the book
    function addNumberOfLike(address _bookAddress, uint256 _tokenId) external {
        require(
            !bookChapterToViewerLike[_bookAddress][_tokenId][msg.sender],
            "Already liked"
        );
        chapterLikeCount[_bookAddress][_tokenId] += 1;
        bookLikeCount[_bookAddress] += 1;
        bookChapterToViewerLike[_bookAddress][_tokenId][msg.sender] = true;
        emit Like(msg.sender, "Like");
    }

    // To allow readers to unlike a chapter of the book
    function removeLike(address _bookAddress, uint256 _tokenId) external {
        require(
            bookChapterToViewerLike[_bookAddress][_tokenId][msg.sender],
            "Not liked"
        );
        chapterLikeCount[_bookAddress][_tokenId] -= 1;
        bookLikeCount[_bookAddress] -= 1;
        bookChapterToViewerLike[_bookAddress][_tokenId][msg.sender] = false;
        emit Like(msg.sender, "Unlike");
    }

    // A generate function to return the book addresses based on the given range
    // The book addresses can come from different arrays
    function getBookAddressesByRange(uint8 _arrayType, uint256 _startIndex, uint256 _endIndex) 
    public view returns (address[] memory) {
        uint256 length = 0;
        address[] memory tempArray;
        // Type 0 -> All book addresses array
        // Type 1 -> Books with new chapter
        // Type 2 -> Books by category
        // Others -> return empty array
        if (_arrayType == 0) {
            tempArray = bookAddresses;
            length = bookAddresses.length;
        } else if (_arrayType == 1) {
            // *** Change this data to offchain ***
            // tempArray = booksWithNewChapter;
            // length = booksWithNewChapter.length;
        } else if (_arrayType == 2) {
            // *** Change this data to offchain ***
            // tempArray = booksByCategory[_category];
            // length = booksByCategory[_category].length;
        } else {
            return new address[](0);
        }

        if (_endIndex > length - 1) {
            _endIndex = length - 1;
        }

        require(_startIndex <= _endIndex, "Invalid range");

        address[] memory bookAddressByRange = new address[](
            _endIndex - _startIndex + 1
        );
        uint256 index = 0;
        uint256 i = length - _startIndex - 1;
        uint256 j = length - _endIndex - 1;

        // return the addresses in reverse order
        // latest book first
        for (i; i > j; i--) {
            bookAddressByRange[index] = tempArray[i];
            index++;
        }
        bookAddressByRange[index] = tempArray[j];
        return bookAddressByRange;
    }

    function getBookAddresses() public view returns (address[] memory) {
        return bookAddresses;
    }

    function getBookAddressesLength() public view returns (uint256) {
        return bookAddresses.length;
    }

    // *** Change this data to offchain ***
    // function getBooksWithNewChapter() public view returns (address[] memory) {
    //     return booksWithNewChapter;
    // }

    // *** Change this data to offchain ***
    // function getbooksWithNewChapterLength() public view returns (uint256) {
    //     return booksWithNewChapter.length;
    // }

    // *** Change this data to offchain ***
    // function getBooksByCategory(uint8 _category) public view returns (address[] memory) {
    //     return booksByCategory[_category];
    // }

    // *** Change this data to offchain ***
    // function getbooksByCategoryLength(uint8 _category) public view returns (uint256) {
    //     return booksByCategory[_category].length;
    // }

    function getViewerFavouriteBooks(address _viewerAddress) public view returns (address[] memory) {
        return viewerFavourite[_viewerAddress];
    }

    function getReportedBooks() public view returns (address[] memory) {
        return reportedBooks;
    }

    function getBlacklistBooks() public view returns (address[] memory) {
        return blacklistBooks;
    }

    function getListOfBooksByAuthor(address _authorAddress) public view returns (address[] memory) {
        return booksByAuthor[_authorAddress];
    }

    function getListOfReportersByBook(address _bookAddress) public view returns (address[] memory) {
        return bookReporters[_bookAddress];
    }

    // *** Change this data to offchain ***
    // function resetBooksWithNewChapter(address[] memory _books) public onlyOwner {
    //   delete booksWithNewChapter;
    //   booksWithNewChapter = _books;
    // }

    function claimMyContractsGas() external onlyOwner{
        BLAST.claimMaxGas(address(this), msg.sender);
    }
}
