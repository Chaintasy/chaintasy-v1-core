// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./Membership.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./IBlast.sol";

contract Book is ERC721URIStorage  {

    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

    uint256 public tokenId;

    // Book Manager contract will function as the owner to control 2 things:
    // 1. Mint new chapter NFT
    // 2. Update paid viewer list
    address public bookManager;

    address public membershipAddress; 

    // Only current author is allowed to mint new chapter NFT
    // Authorship can be transfer, but ownership of existing chapter NFT still remains
    address public author;

    // Some book details
    string public image;
    string public description;
    uint8 public category;
    uint256 public bookCreationTimestamp;
    bool public completed;

    struct BookChapter {
        string chapterTitle;
        string content;
        uint256 fee;
        uint256 chapterCreationTimestamp;
    }

    event NewBook (address, string);
    event UpdateBook (address, string);
    event NewChapter (address, string);
    event UpdateChapter (address, string);
    event ClaimGas (address, string);

    // Keeping track of chapter NFT
    mapping(uint256 => BookChapter) private tokenIdToBook;

    // Keeping track of viewer who has paid fee for the chapter
    mapping(uint256 => mapping(address => bool)) public paidViewerPerChapter;

    // Create new book contract using BookFactory
    constructor(
        string memory _title, 
        address _bookManager, 
        address _membership,
        address _authorAddress, 
        uint8 _category, 
        string memory _image, 
        string memory _description
    ) ERC721 (_title, "BOOK"){
        bookManager = _bookManager;
        membershipAddress = _membership;
        author = _authorAddress;
        description = _description;
        image = _image;
        category = _category;
        bookCreationTimestamp = block.timestamp;
        completed = false;
        BLAST.configureClaimableGas(); 
    }

    // Generate token URI to be stored in NFT
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        BookChapter memory bookChapter = tokenIdToBook[_tokenId];
        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": "', name(), ' - ', bookChapter.chapterTitle, '",',
                '"description": "', description, '",',
                '"image": "', image, '"',
            '}'
        );
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }

    // Mint new chapter NFT. Editable within 10 minutes from creation block time.
    function mintChapter(address _author, string memory _chapterTitle, string memory _content, uint256 _fee) external {
        require(msg.sender == bookManager, "Unauthorise");
        require(!completed, "Book completed");
        tokenId = tokenId + 1;
        uint256 newItemId = tokenId;
        _mint(_author, newItemId);
        tokenIdToBook[newItemId].chapterTitle = _chapterTitle;
        tokenIdToBook[newItemId].content = _content;
        tokenIdToBook[newItemId].fee = _fee;
        tokenIdToBook[newItemId].chapterCreationTimestamp = block.timestamp;
        _setTokenURI(newItemId, tokenURI(newItemId));
        // emit NewChapter(_author, "New Chapter");
    }

    // Update the book details. 
    function updateBook(string memory _image, string memory _description) external {
        require(author == msg.sender, "Unauthorise");
        require(block.timestamp <= bookCreationTimestamp + 10 minutes, "Not allowed to edit");
        description = _description;
        image = _image;
        emit UpdateBook(msg.sender, "Update Book");
    }

    // Update book as Completed
    function updateBookStatus() external {
        require(author == msg.sender, "Unauthorise");
        completed = true;
        emit UpdateBook(msg.sender, "Update Book Status");
    }

    // Update chapter content
    function updateChapter(uint256 _tokenId, string memory _chapterTitle, string memory _content, uint256 _fee) external {
        // require(_exists(_tokenId), "Token ID does not exist");
        require(ownerOf(_tokenId) == msg.sender, "Unauthorise");
        require(block.timestamp <= tokenIdToBook[_tokenId].chapterCreationTimestamp + 10 minutes, "Not allowed to edit");
        tokenIdToBook[_tokenId].chapterTitle = _chapterTitle;
        tokenIdToBook[_tokenId].content = _content;
        tokenIdToBook[_tokenId].fee = _fee;
        _setTokenURI(_tokenId, tokenURI(_tokenId));
        emit UpdateChapter(msg.sender, "Update Chapter");
    }

    // Update chapter fee
    function updateChapterFee(uint256 _tokenId, uint256 _fee) external {
        // require(_exists(_tokenId), "Token ID does not exist");
        require(ownerOf(_tokenId) == msg.sender, "Unauthorise");
        tokenIdToBook[_tokenId].fee = _fee;
        emit UpdateChapter(msg.sender, "Update Chapter Fee");
    }

    // Update viewer paid status from BookManager
    function updatePaidStatus(uint256 _tokenId, address _viewer) external {
        require(msg.sender == bookManager, "Unauthorise");
        paidViewerPerChapter[_tokenId][_viewer] = true;
        // emit UpdateChapter(_viewer, "Chapter Paid");
    }

    // Get chapter content
    // Restrict access depends on whether there is fee for the chapter
    function getChapter(uint256 _tokenId) public view returns(BookChapter memory){
        // require(_exists(_tokenId), "Token ID does not exist");
        Membership membership = Membership(membershipAddress);
        if (ownerOf(_tokenId) == msg.sender || 
            tokenIdToBook[_tokenId].fee <= 0 ||
            paidViewerPerChapter[_tokenId][msg.sender] || 
            membership.checkMembership(msg.sender) ){
            return tokenIdToBook[_tokenId];
        } else {
            return BookChapter(
                tokenIdToBook[_tokenId].chapterTitle, 
                "Pay to view", 
                tokenIdToBook[_tokenId].fee, 
                tokenIdToBook[_tokenId].chapterCreationTimestamp
            );
        }
    }

    function getFeeByChapter(uint256 _tokenId) public view returns (uint256){
        return tokenIdToBook[_tokenId].fee;
    }

    function transferAuthorship(address _newAuthor) public {
        require(msg.sender == author, "Unauthorise");
        author = _newAuthor;
    }

    // Note: in production, you would likely want to restrict access to this
    function claimMyContractsGas() external {
        require(author == msg.sender, "Unauthorise");
        BLAST.claimMaxGas(address(this), msg.sender);
        emit ClaimGas(msg.sender, "Gas claimed");
    }

    // function getBookChapterLength() public view returns (uint256){
    //     return tokenId;
    // }

    // The following functions are overrides required by Solidity.

    // function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
    //     internal
    //     override(ERC721, ERC721Enumerable)
    // {
    //     require(
    //          block.timestamp > tokenIdToBook[tokenId].chapterCreationTimestamp + 10 minutes, 
    //          "Transfer not allow within 10 minutes" 
    //     );
    //     super._beforeTokenTransfer(from, to, tokenId, batchSize);
    // }

    // function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
    //     super._burn(tokenId);
    // }

    // function supportsInterface(bytes4 interfaceId)
    //     public
    //     view
    //     override(ERC721, ERC721Enumerable)
    //     returns (bool)
    // {
    //     return super.supportsInterface(interfaceId);
    // }

}