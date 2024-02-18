// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Book.sol";

contract BookFactory is Ownable {
  
  IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

  constructor() {
    BLAST.configureClaimableGas();
  }

  function newBook(
    address _author, 
    address _membership,
    string memory _title, 
    uint8 _category, 
    string memory _image, 
    string memory _description
  ) public returns(address){
    Book book = new Book(_title, msg.sender, _membership, _author, _category, _image, _description); 
    return address(book);
  }

  function claimMyContractsGas() external onlyOwner{
    BLAST.claimMaxGas(address(this), msg.sender);
  }
}



