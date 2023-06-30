// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract Mortgage is IERC721Receiver {
    using SafeMath for uint256;
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

    Pool[] public pools;
    Loan[] public loans;
    //gia san` cua moi pool
    mapping(address => uint256) public floorPrice;
    mapping(address => address)  public lenderToBorrower;
    mapping(uint256 => mapping(address => uint256)) public poolLenderFunds;
    mapping(address => bool) public poolTokenAddress;
    uint256 public poolCounter;
    uint256 public loanCounter;
    //mapping addressToLoan

    mapping(address => Loan[]) public lenderLoans;

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
        uint256 poolId = poolCounter;
        pools.push(Pool({
            poolId: poolId,
            tokenAddress: _tokenAddress,
            totalPoolAmount: 0,
            APY: _APY,
            duration: _duration,
            state: true
        }));
        poolCounter++;

        poolTokenAddress[_tokenAddress] = true;

        emit PoolCreated(poolId, _tokenAddress, 0, _APY, _duration, true);
    }

    function UpdatePool(uint256 _poolId, uint256 _APY, uint256 _duration, bool _state) external {
        pools[_poolId].state = _state;
        pools[_poolId].APY = _APY;
        pools[_poolId].duration = _duration;

        emit UpdatedPool(_poolId, _APY, _duration, _state);
    }

    function LenderOffer(uint256 _poolId) external payable {
        require(_poolId < poolCounter, "Pool does not exist");
        require(pools[_poolId].state == true, "Pool is closed");
        uint256 price = getFloorPrice(pools[_poolId].tokenAddress);
        require(msg.value == price);
        pools[_poolId].totalPoolAmount += msg.value;

        uint256 loanId = loanCounter;
        //create a Loan
        loans.push(Loan({
            loanId: loanId,
            lender: msg.sender,
            borrower: address(0),
            amount: msg.value,
            startTime: 0,
            duration: pools[_poolId].duration,
            tokenId: 0,
            poolId: _poolId,
            tokenAddress: pools[_poolId].tokenAddress,
            state: false
        }));
        loanCounter++;

        poolLenderFunds[_poolId][msg.sender] = poolLenderFunds[_poolId][msg.sender].add(msg.value);

        emit OfferMade(_poolId, pools[_poolId].tokenAddress, msg.value, pools[_poolId].APY, pools[_poolId].duration, pools[_poolId].state, msg.sender);
    }

    function LenderRevokeOffer(uint256 _poolId) external {
        require(_poolId < pools.length, "Pool does not exist");
        require(pools[_poolId].state == true, "Pool is closed");
        uint256 price = getFloorPrice(pools[_poolId].tokenAddress);
        require(poolLenderFunds[_poolId][msg.sender] >= price, "You did not offered!");
        pools[_poolId].totalPoolAmount -= price;
        //transfer msg.value to lender
        payTo(msg.sender, price);
        poolLenderFunds[_poolId][msg.sender] = poolLenderFunds[_poolId][msg.sender].sub(price);

        emit OfferRevoke(_poolId, pools[_poolId].tokenAddress, price, pools[_poolId].APY, pools[_poolId].duration, pools[_poolId].state, msg.sender);
    }

    function BorrowerTakeLoan(uint256 _poolId, uint256 _tokenId, uint256 _loanId) external {
        require(_poolId < poolCounter, "Pool does not exist");
        require(pools[_poolId].state == true, "Pool is closed");
        require(pools[_poolId].totalPoolAmount > 0, "Pool is empty");

        loans[_loanId].borrower = msg.sender;
        loans[_loanId].startTime = block.timestamp;
        loans[_loanId].tokenId = _tokenId;
        loans[_loanId].state = true;

        IERC721 token = IERC721(pools[_poolId].tokenAddress);
        require(
            token.ownerOf(_tokenId) == msg.sender,
            "You do not own the NFT"
        );
        //aprove by code first
        token.safeTransferFrom(msg.sender, address(this), _tokenId);
        uint256 price = getFloorPrice(pools[_poolId].tokenAddress);
        pools[_poolId].totalPoolAmount -= price;
        payTo(msg.sender, price);
        emit BorrowerOffer(_poolId, pools[_poolId].tokenAddress, price, _tokenId, pools[_poolId].APY, pools[_poolId].duration, pools[_poolId].state, msg.sender, msg.sender);
    }
    
    function BorrowerPayLoan(uint256 _poolId, uint256 _tokenId, address _lender, uint256 _loanId) external payable {
        require(pools[_poolId].state == true, "Pool is closed");
        
        uint256 startTime = loans[_loanId].startTime;
        require(block.timestamp < startTime + pools[_poolId].duration * 86400 , "Loan is passed");
        uint256 durations = (block.timestamp - startTime)/86400;
        if (durations < pools[_poolId].duration){
            //prevent spamming loan
            durations += 1;
        } 
        uint256 interest = (loans[_loanId].amount * pools[_poolId].APY * durations)/100/365;

        IERC721 token = IERC721(pools[_poolId].tokenAddress);
        require(
            token.ownerOf(_tokenId) == address(this),
            "the NFT does not in the pool"
        );
        token.safeTransferFrom(address(this), msg.sender, _tokenId);
        uint256 totalAmount = loans[_loanId].amount.add(interest);
        require(msg.value >= totalAmount, "Insufficient payment");
        payTo(_lender, totalAmount);
        // Update the pool's totalPoolAmount
        // pools[_poolId].totalPoolAmount = pools[_poolId].totalPoolAmount.sub(loans[_loanId].amount);
        poolLenderFunds[_poolId][_lender] = poolLenderFunds[_poolId][_lender].sub(loans[_loanId].amount);
        //delete loan
        delete loans[_loanId];
        
        emit PayLoan(_poolId, pools[_poolId].tokenAddress, totalAmount, _tokenId, pools[_poolId].APY, pools[_poolId].duration, msg.sender, msg.sender);
    }

    function LenderClaimNFT(uint256 _poolId, uint256 _tokenId, uint256 _loanId) external {
        Pool storage pool = pools[_poolId];
        require(pool.state == true, "Pool is closed");
        require(loans[_loanId].lender == msg.sender, "Only the lender can claim the NFT");
        require(loans[_loanId].tokenId == _tokenId, "Token ID does not match the loan");
        require(block.timestamp > loans[_loanId].startTime + loans[_loanId].duration * 86400, "Loan duration has not passed");

        IERC721 token = IERC721(loans[_loanId].tokenAddress);
        require(token.ownerOf(_tokenId) == address(this), "NFT is not held by the contract");

        token.safeTransferFrom(address(this), loans[_loanId].lender, _tokenId);
        poolLenderFunds[_poolId][msg.sender] = poolLenderFunds[_poolId][msg.sender].sub(loans[_loanId].amount);

        delete loans[_loanId];

        emit LenderClaimToken(
            _poolId,
            loans[_loanId].tokenAddress,
            loans[_loanId].amount,
            _tokenId,
            pool.APY,
            pool.duration,
            loans[_loanId].state,
            loans[_loanId].lender,
            loans[_loanId].borrower
        );
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

    function getAllPool() external view returns(Pool[] memory) {
        return pools;
    }

    function getExactPool(uint256 _poolId) external view returns(Pool memory) {
        return pools[_poolId];
    }

    function getAllLoans() external view returns(Loan[] memory) {
        return loans;
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