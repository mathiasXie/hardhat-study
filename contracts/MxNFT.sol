// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MxNFT is ERC721, Ownable {

    uint256 public nextId;

    constructor(string memory name, string memory symbol) 
        ERC721(name, symbol) 
        Ownable(msg.sender) 
    {}

    function mint(address to) external onlyOwner returns (uint256) {
        uint256 id = nextId++;
        _mint(to, id);
        return id;
    }

    function burn(uint256 tokenId) external {
        require(msg.sender == ownerOf(tokenId), "not owner");
        _burn(tokenId);
    }
}