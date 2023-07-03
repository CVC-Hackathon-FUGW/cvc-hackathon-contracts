// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract NFTMarket is ReentrancyGuard, IERC721Receiver {
    using Counters for Counters.Counter;
    Counters.Counter private _itemIds;
    Counters.Counter private _itemsSold;

    address owner;
    uint256 listingPrice = 10000000000000000;
    //default listing price = 0.01 ether

    constructor() {
        owner = msg.sender;
    }

    struct MarketItem {
        uint itemId;
        address nftContract;
        uint256 tokenId;
        address  seller;
        address  owner;
        uint256 price;
        bool isOfferable;
        bool acceptVisaPayment;
        uint256 currentOfferValue;
        address  currentOfferer;
        bool sold;
    }

    mapping(uint256 => MarketItem) private idToMarketItem;

    event MarketItemCreated(
        uint indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price
    );

    function GetMarketItem(
        uint256 marketItemId
    ) public view returns (MarketItem memory) {
        return idToMarketItem[marketItemId];
    }

    function CreateMarketItem(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isVisaAccepted,
        bool isOfferable
    ) public payable nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        require(
            msg.value == listingPrice,
            "Price must be equal to listing price"
        );

        _itemIds.increment();
        uint256 itemId = _itemIds.current();

        idToMarketItem[itemId] = MarketItem(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(0),
            price,
            isOfferable,
            isVisaAccepted,
            0,
            address(0),
            false
        );

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        emit MarketItemCreated(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(0),
            price
        );
    }

    function Buy(
        address nftContract,
        uint256 itemId
    ) public payable nonReentrant {
        uint price = idToMarketItem[itemId].price;
        uint tokenId = idToMarketItem[itemId].tokenId;
        require(
            msg.value == price,
            "Please submit the asking price in order to complete the purchase"
        );

        if(idToMarketItem[itemId].currentOfferValue > 0 && idToMarketItem[itemId].currentOfferer != address(0)){
            //transfer back to previous offerer
            payTo(idToMarketItem[itemId].currentOfferer, idToMarketItem[itemId].currentOfferValue);
        }
        payTo(idToMarketItem[itemId].seller, msg.value);
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        idToMarketItem[itemId].owner = msg.sender;
        idToMarketItem[itemId].sold = true;
        _itemsSold.increment();
        payTo(owner, listingPrice);
    }

    function InstantBuy(address nftContract, uint256 itemId, bool purchased) public nonReentrant {
        require(purchased, "User did not purchase item by Visa method");
        uint tokenId = idToMarketItem[itemId].tokenId;

        if(idToMarketItem[itemId].currentOfferValue > 0 && idToMarketItem[itemId].currentOfferer != address(0)){
            //transfer back to previous offerer
            payTo(idToMarketItem[itemId].currentOfferer, idToMarketItem[itemId].currentOfferValue);
        }
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
    }

    function OfferMarketItem(uint256 itemId) public payable nonReentrant {
        require(idToMarketItem[itemId].isOfferable, "This item is not available to offer!");
        require(msg.value > idToMarketItem[itemId].currentOfferValue, "This item has a higher offer value!");

        if(idToMarketItem[itemId].currentOfferValue > 0 && idToMarketItem[itemId].currentOfferer != address(0)){
            //transfer back to previous offerer
            payTo(idToMarketItem[itemId].currentOfferer, idToMarketItem[itemId].currentOfferValue);
        }
        // uint256 tokenId = idToMarketItem[itemId].tokenId;

        idToMarketItem[itemId].currentOfferValue = msg.value;
        idToMarketItem[itemId].currentOfferer = msg.sender;
    }

    function CancelListing(address nftContract, uint256 itemId) public nonReentrant{
        require(msg.sender == idToMarketItem[itemId].seller, "You are not seller!");
        uint tokenId = idToMarketItem[itemId].tokenId;
        if(idToMarketItem[itemId].currentOfferValue > 0 && idToMarketItem[itemId].currentOfferer != address(0)){
            //transfer back to previous offerer
            payTo(idToMarketItem[itemId].currentOfferer, idToMarketItem[itemId].currentOfferValue);
        }

        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        payTo(owner, listingPrice);

        delete idToMarketItem[itemId];
    }

    function AcceptOffer(address nftContract, uint256 itemId) public nonReentrant {
        uint tokenId = idToMarketItem[itemId].tokenId;
        IERC721(nftContract).transferFrom(address(this), idToMarketItem[itemId].currentOfferer, tokenId);
        _itemsSold.increment();
        idToMarketItem[itemId].owner = idToMarketItem[itemId].currentOfferer;
        idToMarketItem[itemId].sold = true;

        payTo(msg.sender, idToMarketItem[itemId].currentOfferValue);
    }

    function payTo(address to, uint amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success);
    }

    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint itemCount = _itemIds.current();
        uint unsoldItemCount = _itemIds.current() - _itemsSold.current();
        uint currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint i = 0; i < itemCount; i++) {
            if (idToMarketItem[i + 1].owner == address(0)) {
                uint currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint totalItemCount = _itemIds.current();
        uint itemCount = 0;
        uint currentIndex = 0;

        for (uint i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                uint currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }
    function setListingPrice(uint256 price) public {
        require(msg.sender == owner, "Only owner can set listing price");
        listingPrice = price;
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
}
