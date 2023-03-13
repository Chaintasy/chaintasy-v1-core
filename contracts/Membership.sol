// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Membership is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    uint256 public constant MAX_SUPPLY = 9999;
    uint256 public constant MAX_PER_MINT = 5;
    uint256 public constant PRICE_PER_MINT = 20 ether;
    string public baseTokenURI;

    mapping(uint256 => uint256) public tokenIdMembershipExpiry;
    uint256 public SUBSCRIPTION_FEE_30DAYS;
    uint256 public SUBSCRIPTION_FEE_180DAYS;
    uint256 public SUBSCRIPTION_FEE_365DAYS;

    // Pool of tokens accepted as subscription fee
    // 0 -> USDC, 1 -> USDT
    IERC20[] public subscriptionTokenPool;
    uint256[] public subscriptionTokenBalance;

    struct SubscriptionHistory {
        address subscriber;
        // 0 -> 30 Days, 1 -> 180 Days, 2 -> 365 Days
        uint8 subscriptionPlan;
        uint256 subscriptionAmount;
        uint256 subscriptionExpiry;
    }

    constructor() ERC721("Chaintasy Membership", "CTYM") {
        pause();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    modifier saleIsOpen {
        require(totalSupply() <= MAX_SUPPLY, "Sale has ended");
        if (_msgSender() != owner()) {
            require(!paused(), "Pausable: paused");
        }
        _;
    }

    function mint(address _to, uint256 _count) public payable saleIsOpen {
        uint256 total = totalSupply();
        uint256 totalPrice = PRICE_PER_MINT * _count;
        require(total + _count <= MAX_SUPPLY, "Exceeds max limit");
        require(total <= MAX_SUPPLY, "Sale has ended");
        require(_count <= MAX_PER_MINT, "Exceeds max per mint");
        require(msg.value >= totalPrice, "Value below price");

        for (uint256 i = 0; i < _count; i++) {
            safeMint(_to);
        }
    }

    function safeMint(address to) private {
        uint256 tokenId = _tokenIdCounter.current();
         _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, generateURI(Strings.toString(tokenId)));
    }

    // Generate token URI to be stored in NFT
    function generateURI(string memory tokenId) public view returns (string memory) {
        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": "', name(), ' # ', tokenId, '", ',
                '"description": "Chaintasy Membership NFT with different utilities", ',
                '"image": "', baseTokenURI, 'Chaintasy/', tokenId, '.png"',
            '}'
        );
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }

    function withdrawAll() public payable onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Insufficient Balance");
        _widthdraw(owner(), address(this).balance);
    }

    function _widthdraw(address _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function checkMembership(address _ownerAddress) external view returns (bool) {
        uint256 tokenCount = balanceOf(_ownerAddress);
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_ownerAddress, i);
            if (tokenIdMembershipExpiry[tokenId] >= block.timestamp) {
                return true;
            }
        }
        return false;
    }

    function getTokensOfOwner() external view returns (uint256[] memory){
        uint256 tokenCount = balanceOf(msg.sender);
        uint256[] memory tokens = new uint[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);
            tokens[i] = tokenId;
        }
        return tokens;
    }

    function subscribeMembership(
        uint256 _tokenId, 
        uint8 _subscriptionStablecoinType, 
        uint8 _subscriptionPlan
    ) external {
        // require(tokenIdMembershipExpiry[_tokenId] < block.timestamp, "Membership not expired");

        // Extend subscription expiry depending on the plan
        uint256 subscriptionFee;
        if (_subscriptionPlan == 0){
            subscriptionFee = SUBSCRIPTION_FEE_30DAYS;
            if (tokenIdMembershipExpiry[_tokenId] < block.timestamp){
                tokenIdMembershipExpiry[_tokenId] = block.timestamp + 30 days;
            } else {
                tokenIdMembershipExpiry[_tokenId] = tokenIdMembershipExpiry[_tokenId] + 30 days;
            }
        } else if (_subscriptionPlan == 1){
            subscriptionFee = SUBSCRIPTION_FEE_180DAYS;
            if (tokenIdMembershipExpiry[_tokenId] < block.timestamp){
                tokenIdMembershipExpiry[_tokenId] = block.timestamp + 180 days;
            } else {
                tokenIdMembershipExpiry[_tokenId] = tokenIdMembershipExpiry[_tokenId] + 180 days;
            }
        } else {
            subscriptionFee = SUBSCRIPTION_FEE_365DAYS;
            if (tokenIdMembershipExpiry[_tokenId] < block.timestamp){
                tokenIdMembershipExpiry[_tokenId] = block.timestamp + 365 days;
            } else {
                tokenIdMembershipExpiry[_tokenId] = tokenIdMembershipExpiry[_tokenId] + 365 days;
            }
        }
        
        subscriptionTokenBalance[_subscriptionStablecoinType] += subscriptionFee;

        IERC20 stablecoinToken = IERC20(subscriptionTokenPool[_subscriptionStablecoinType]);
        require(stablecoinToken.transferFrom(msg.sender, owner(), subscriptionFee), "Unsuccessful payment");

    }

    function updateSubscriptionFee(uint8 _subscriptionType, uint256 _amount) external onlyOwner {
        if (_subscriptionType == 0){
            SUBSCRIPTION_FEE_30DAYS = _amount;
        } else if (_subscriptionType == 1){
            SUBSCRIPTION_FEE_180DAYS = _amount;
        } else {
            SUBSCRIPTION_FEE_365DAYS = _amount;
        }
    }

    // Add the list of payment tokens for Sale and Purchase of chapter NFTs
    function addSubscriptionToken(address _tokenAddress) public onlyOwner {
        for (uint8 i; i < subscriptionTokenPool.length; i++){
            require(subscriptionTokenPool[i] != IERC20(_tokenAddress), "Already exist");
        }
        subscriptionTokenPool.push(IERC20(_tokenAddress));
        subscriptionTokenBalance.push(0);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}