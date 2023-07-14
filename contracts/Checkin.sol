// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract Checkin is ERC20, IERC721Receiver {
    //we will mint for this address 20 nft, and send to user when they convert to gift.
    //also send here 5 CVC
    address nftAddress;
    uint256 nftCount = 20;
    address owner;
    constructor(address _nftAddress) ERC20("Rental", "RENT"){
        owner = msg.sender;
        nftAddress = _nftAddress;
        _mint(address(this), 10000000 * 10**decimals());
        _mint(msg.sender, 1000000000 * 10**decimals());
    }

    mapping (address => uint256) private lastCheckin;

    function checkin() external {
        require(lastCheckin[msg.sender] + 1 days < block.timestamp, "You can only checkin once a day");
        lastCheckin[msg.sender] = block.timestamp;
        _transfer(address(this), msg.sender, 100);
    }

    //remember to approve first
    function exchangeToGift(uint256 amount) external {
        require(amount > 1000, "Minimum convert amount is 1000 RENT");
        require(amount <= 10000, "Maximum convert amount is 10000 RENT");
        require(balanceOf(msg.sender) >= amount, "You don't have enough RENT token");
        //1000 token = 0.01 XCR
        if (amount < 10000) {
            _transfer(msg.sender, owner, amount);
            payTo(msg.sender, amount * 10000000000000);
        }else if (amount == 10000) {
            require(nftCount > 0, "No more NFT left");
            _transfer(msg.sender, owner, amount);
            IERC721 token = IERC721(nftAddress);
            token.safeTransferFrom(address(this), msg.sender, nftCount);
            nftCount--;
        }
    }

    function payTo(address to, uint amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function getNFTsLeft() external view returns (uint256) {
        return nftCount;
    }

    function getBalanceLeft() external view returns (uint256) {
        return address(this).balance;
    }
}