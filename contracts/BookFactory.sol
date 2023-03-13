// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Book.sol";

contract BookFactory {

  constructor() {}

  function newBook(
    address _author, 
    address _membership,
    string memory _title, 
    uint8 _category, 
    string memory _image, 
    string memory _description, 
    address _auditor
  ) public returns(address){
    Book book = new Book(_title, msg.sender, _membership, _author, _category, _image, _description, _auditor); 
    return address(book);
  }
}



