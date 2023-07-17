// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract Mortgage is IERC721Receiver {
    using SafeMath for uint256;
    uint256 borrowPrice = 1000000000000000;
    //default borrow price is 0.001 XRC
    struct Loan {
        uint256 loanId;
        address lender;
        address borrower;
        uint256 amount;
        uint256 startTime;
        uint256 duration;
        uint256 tokenId;
        uint256 poolId;
        address tokenAddress;
        bool state;
    }

    struct Pool {
        uint256 poolId;
        address tokenAddress;
        uint256 totalPoolAmount;
        uint256 APY;
        uint256 duration;
        bool state;
    }

    address public owner;

    mapping(uint256 => Loan) public idToLoan;
    mapping(uint256 => Pool) public idToPool;
    //gia san` cua moi pool
    mapping(address => uint256) public floorPrice;
    mapping(uint256 => mapping(address => uint256)) public poolLenderFunds;
    mapping(address => bool) public poolTokenAddress;
    uint256 public poolCounter;
    uint256 public loanCounter;

    event PoolCreated(
        uint256 indexed poolId,
        address indexed tokenAddress,
        uint256 indexed totalPoolAmount,
        uint256 APY,
        uint256 duration,
        bool state
    );

    event UpdatedPool(
        uint256 indexed poolId,
        uint256 APY,
        uint256 duration,
        bool state
    );

    event OfferMade(
        uint256 indexed poolId,
        address indexed tokenAddress,
        uint256 indexed amount,
        uint256 APY,
        uint256 duration,
        bool state,
        address lender
    );

    event OfferRevoke(
        uint256 indexed poolId,
        address indexed tokenAddress,
        uint256 indexed amount,
        uint256 APY,
        uint256 duration,
        bool state,
        address lender
    );

    event BorrowerOffer(
        uint256 indexed poolId,
        address indexed tokenAddress,
        uint256 indexed receiverAmount,
        uint256 tokenId,
        uint256 APY,
        uint256 duration,
        bool state,
        address lender,
        address borrower
    );

    event PayLoan(
        uint256 indexed poolId,
        address indexed tokenAddress,
        uint256 indexed receiverAmount,
        uint256 tokenId,
        uint256 APY,
        uint256 duration,
        address lender,
        address borrower
    );  

    event LenderClaimToken(
        uint256 indexed poolId,
        address indexed tokenAddress,
        uint256 indexed receiverAmount,
        uint256 tokenId,
        uint256 APY,
        uint256 duration,
        bool state,
        address lender,
        address borrower
    );

    constructor() {
        owner = msg.sender;
        loanCounter = 0;
        poolCounter = 0;
    }

    function CreatePool(address _tokenAddress, uint256 _APY, uint256 _duration) external onlyAdmin {
        require(_APY > 0, "APY must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(_tokenAddress != address(0), "Token address must be valid");
        require(!poolTokenAddress[_tokenAddress], "Token address already exists");    
        poolCounter++;
        uint256 poolId = poolCounter;

        idToPool[poolId] = Pool({
            poolId: poolId,
            tokenAddress: _tokenAddress,
            totalPoolAmount: 0,
            APY: _APY,
            duration: _duration,
            state: true
        });


        poolTokenAddress[_tokenAddress] = true;

        emit PoolCreated(poolId, _tokenAddress, 0, _APY, _duration, true);
    }

    function UpdatePool(uint256 _poolId, uint256 _APY, uint256 _duration, bool _state) external onlyAdmin {
        idToPool[_poolId].state = _state;
        idToPool[_poolId].APY = _APY;
        idToPool[_poolId].duration = _duration;

        emit UpdatedPool(_poolId, _APY, _duration, _state);
    }

    function LenderOffer(uint256 _poolId) external payable {
        require(idToPool[_poolId].state == true, "Pool is closed");
        uint256 price = getFloorPrice(idToPool[_poolId].tokenAddress);
        require(msg.value >= price, "Offer must be higher than floor price!");
        idToPool[_poolId].totalPoolAmount += msg.value;
        loanCounter++;
        uint256 loanId = loanCounter;
        //create a Loan

        idToLoan[loanId] = Loan({
            loanId: loanId,
            lender: msg.sender,
            borrower: address(0),
            amount: msg.value,
            startTime: 0,
            duration: idToPool[_poolId].duration,
            tokenId: 0,
            poolId: _poolId,
            tokenAddress: idToPool[_poolId].tokenAddress,
            state: false
        });

        poolLenderFunds[_poolId][msg.sender] = poolLenderFunds[_poolId][msg.sender].add(msg.value);

        emit OfferMade(_poolId, idToPool[_poolId].tokenAddress, msg.value, idToPool[_poolId].APY, idToPool[_poolId].duration, idToPool[_poolId].state, msg.sender);
    }

    function LenderRevokeOffer(uint256 _poolId, uint256 _loanId) external {
        require(idToPool[_poolId].state == true, "Pool is closed");
        require(idToLoan[_loanId].lender == msg.sender, "You are not the lender of this loan");
        uint256 value = idToLoan[_loanId].amount;
        require(poolLenderFunds[_poolId][msg.sender] >= value, "You did not offered!");
        idToPool[_poolId].totalPoolAmount -= value;
        //transfer msg.value to lender
        payTo(msg.sender, value);
        poolLenderFunds[_poolId][msg.sender] = poolLenderFunds[_poolId][msg.sender].sub(value);

        delete idToLoan[_loanId];

        emit OfferRevoke(_poolId, idToPool[_poolId].tokenAddress, value, idToPool[_poolId].APY, idToPool[_poolId].duration, idToPool[_poolId].state, msg.sender);
    }

    function BorrowerTakeLoan(uint256 _poolId, uint256 _tokenId, uint256 _loanId) external {
        require(idToPool[_poolId].state == true, "Pool is closed");
        require(idToPool[_poolId].totalPoolAmount > 0, "Pool is empty");

        idToLoan[_loanId].borrower = msg.sender;
        idToLoan[_loanId].startTime = block.timestamp;
        idToLoan[_loanId].tokenId = _tokenId;
        idToLoan[_loanId].state = true;

        IERC721 token = IERC721(idToPool[_poolId].tokenAddress);
        require(
            token.ownerOf(_tokenId) == msg.sender,
            "You do not own the NFT"
        );
        //aprove by code first
        token.safeTransferFrom(msg.sender, address(this), _tokenId);

        uint256 value = idToLoan[_loanId].amount;
        idToPool[_poolId].totalPoolAmount -= value;
        payTo(msg.sender, value);
        emit BorrowerOffer(_poolId, idToPool[_poolId].tokenAddress, value, _tokenId, idToPool[_poolId].APY, idToPool[_poolId].duration, idToPool[_poolId].state, msg.sender, msg.sender);
    }
    
    function BorrowerPayLoan(uint256 _poolId, uint256 _loanId) external payable {
        require(idToPool[_poolId].state == true, "Pool is closed");
        uint256 _tokenId = idToLoan[_loanId].tokenId;
        address lender = idToLoan[_loanId].lender;
        
        uint256 startTime = idToLoan[_loanId].startTime;
        require(block.timestamp < startTime + idToPool[_poolId].duration * 86400 , "Loan is passed");
        uint256 durations = (block.timestamp - startTime)/86400;
        if (durations < idToPool[_poolId].duration){
            //prevent spamming loan
            durations += 1;
        } 
        uint256 interest = (idToLoan[_loanId].amount * idToPool[_poolId].APY * durations)/100/365;

        IERC721 token = IERC721(idToPool[_poolId].tokenAddress);
        require(
            token.ownerOf(_tokenId) == address(this),
            "the NFT does not in the pool"
        );
        token.safeTransferFrom(address(this), msg.sender, _tokenId);
        uint256 totalAmount = idToLoan[_loanId].amount.add(interest);
        require(msg.value >= totalAmount, "Insufficient payment");
        payTo(owner, borrowPrice);
        payTo(lender, totalAmount);

        poolLenderFunds[_poolId][lender] = poolLenderFunds[_poolId][lender].sub(idToLoan[_loanId].amount);
        //delete loan
        delete idToLoan[_loanId];
    }

    function LenderClaimNFT(uint256 _poolId, uint256 _loanId) external payable {
        Pool storage pool = idToPool[_poolId];
        require(msg.value == borrowPrice, "You must pay the borrow price!");
        require(pool.state == true, "Pool is closed");
        require(idToLoan[_loanId].lender == msg.sender, "Only the lender can claim the NFT");
        require(block.timestamp > idToLoan[_loanId].startTime + idToLoan[_loanId].duration * 86400, "Loan duration has not passed");
        uint256 _tokenId = idToLoan[_loanId].tokenId;
        IERC721 token = IERC721(idToLoan[_loanId].tokenAddress);
        require(token.ownerOf(_tokenId) == address(this), "NFT is not held by the contract");

        payTo(owner, msg.value);
        token.safeTransferFrom(address(this), idToLoan[_loanId].lender, _tokenId);
        poolLenderFunds[_poolId][msg.sender] = poolLenderFunds[_poolId][msg.sender].sub(idToLoan[_loanId].amount);

        delete idToLoan[_loanId];

        emit LenderClaimToken(
            _poolId,
            idToLoan[_loanId].tokenAddress,
            idToLoan[_loanId].amount,
            _tokenId,
            pool.APY,
            pool.duration,
            idToLoan[_loanId].state,
            idToLoan[_loanId].lender,
            idToLoan[_loanId].borrower
        );
    }

    function setBorrowPrice(uint256 price) external onlyAdmin {
        borrowPrice = price;
    }

    function payTo(address to, uint amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success);
    }

    modifier onlyAdmin() {
        require(msg.sender == owner, "Only admin can call this function");
        _;
    }
    function setFloorPrice(address _tokenAddress, uint256 _floorPrice) external onlyAdmin {
        floorPrice[_tokenAddress] = _floorPrice;
    }

    function getFloorPrice(address _tokenAddress) public view returns(uint256) {
        return floorPrice[_tokenAddress];
    }

    function getExactPool(uint256 _poolId) external view returns(Pool memory) {
        return idToPool[_poolId];
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