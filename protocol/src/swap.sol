// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Swapper {
    using SafeERC20 for IERC20;

    address public owner;
    bool internal locked;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    struct Token {
        address tokenAddress;
        uint256 decimal;
        string name;
    }

    struct LiquidityPool {
        uint256 token1Id;
        uint256 token2Id;
        uint256 token1Balance;
        uint256 token2Balance;
    }

    // Prices are fixed-point scaled to 1e18 (18 decimals)
    mapping(uint256 => uint256) public tokenPrice;
    uint256 public constant ETH_PRICE_USD = 255600000000000000; // 0.2556 * 1e18
    uint256 public constant USDT_PRICE_USD = 1 * 1000000000000000000; // 1 * 1e18
    uint256 public constant DAI_PRICE_USD = 1 * 1000000000000000000; // 1 * 1e18
    uint256 public constant HDF_PRICE_ETH = 132000000000000; // 0.000132 * 1e18

    mapping(uint256 => Token) public tokens;
    uint256 public tokenCount;

    mapping(bytes32 => LiquidityPool) public pools;
    mapping(bytes32 => bool) public poolExists;

    event SwapExecuted(address indexed user, uint256 fromTokenId, uint256 toTokenId, uint256 fromAmount, uint256 toAmount);
    event LiquidityAdded(address indexed provider, uint256 token1Id, uint256 token2Id, uint256 token1Amount, uint256 token2Amount);
    event LiquidityRemoved(address indexed provider, uint256 token1Id, uint256 token2Id, uint256 token1Amount, uint256 token2Amount);

    constructor() {
        owner = msg.sender;

        tokens[0] = Token(address(0), 18, "ETH");
        tokenPrice[0] = ETH_PRICE_USD;

        tokens[1] = Token(address(0x5828810bed27a3174C594D5c6DC92DeC9A488876), 18, "USDT");
        tokenPrice[1] = USDT_PRICE_USD;

        tokens[2] = Token(address(0x1e3a8726cF3B3536352FAeDF35b3201dE2a323dF), 18, "DAI");
        tokenPrice[2] = DAI_PRICE_USD;

        tokens[3] = Token(address(0xB4e344aC158186B66B0ab62F880dbf63B6AFdA04), 18, "HDF");
        tokenPrice[3] = (HDF_PRICE_ETH * ETH_PRICE_USD) / 1000000000000000000;

        tokenCount = 4;
    }

    // Utility: Normalize token pair order, always returns (smallerId, largerId, corresponding amounts in order)
    function _normalizePair(
        uint256 _tokenAId,
        uint256 _tokenBId,
        uint256 _amountA,
        uint256 _amountB
    ) internal pure returns (uint256 token1Id, uint256 token2Id, uint256 amount1, uint256 amount2) {
        if (_tokenAId < _tokenBId) {
            return (_tokenAId, _tokenBId, _amountA, _amountB);
        } else {
            return (_tokenBId, _tokenAId, _amountB, _amountA);
        }
    }

    // Calculates amount of destination token to receive based on hardcoded prices
    function _calculateSwapAmount(
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _amountToSwap,
        uint256 _fromDecimal,
        uint256 _toDecimal
    ) internal view returns (uint256) {
        uint256 fromPrice = tokenPrice[_fromTokenId];
        uint256 toPrice = tokenPrice[_toTokenId];
        require(fromPrice > 0 && toPrice > 0, "Invalid price data");

        uint256 amountToReceive = (_amountToSwap * fromPrice) / toPrice;

        // Adjust for decimals difference between tokens
        return (amountToReceive * (10 ** _toDecimal)) / (10 ** _fromDecimal);
    }

    // Swap ERC20 -> ERC20 (neither side ETH)
    function swapTokensForTokens(
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _amountToSwap
    ) external nonReentrant returns (bool) {
        require(_fromTokenId < tokenCount && _toTokenId < tokenCount, "Invalid token ID");
        require(_fromTokenId != 0 && _toTokenId != 0, "Use ETH swap functions for ETH");
        require(_fromTokenId != _toTokenId, "Cannot swap same token");
        require(_amountToSwap > 0, "Invalid amount");

        Token memory fromToken = tokens[_fromTokenId];
        Token memory toToken = tokens[_toTokenId];

        require(IERC20(fromToken.tokenAddress).allowance(msg.sender, address(this)) >= _amountToSwap, "Insufficient allowance");

        // Normalize pair for consistent pool access
        (uint256 token1Id, uint256 token2Id, , ) = _normalizePair(_fromTokenId, _toTokenId, 0, 0);
        bytes32 pairId = keccak256(abi.encodePacked(token1Id, token2Id));
        require(poolExists[pairId], "Liquidity pool does not exist");
        LiquidityPool storage pool = pools[pairId];

        uint256 amountToReceive = _calculateSwapAmount(_fromTokenId, _toTokenId, _amountToSwap, fromToken.decimal, toToken.decimal);

        // Determine which side in the pool is the toToken
        uint256 toTokenBalance = (_toTokenId == pool.token1Id) ? pool.token1Balance : pool.token2Balance;
        require(toTokenBalance >= amountToReceive, "Insufficient liquidity");

        IERC20(fromToken.tokenAddress).safeTransferFrom(msg.sender, address(this), _amountToSwap);
        IERC20(toToken.tokenAddress).safeTransfer(msg.sender, amountToReceive);

        // Update pool balances with optimized storage writes
        if (_fromTokenId == pool.token1Id) {
            pool.token1Balance = pool.token1Balance + _amountToSwap;
            pool.token2Balance = pool.token2Balance - amountToReceive;
        } else {
            pool.token1Balance = pool.token1Balance - amountToReceive;
            pool.token2Balance = pool.token2Balance + _amountToSwap;
        }

        emit SwapExecuted(msg.sender, _fromTokenId, _toTokenId, _amountToSwap, amountToReceive);
        return true;
    }

    // ETH -> Token
    function swapEthForTokens(uint256 _tokenId) external payable nonReentrant returns (bool) {
        require(_tokenId < tokenCount, "Invalid token ID");
        require(_tokenId != 0, "Cannot swap to ETH");
        require(msg.value > 0, "Invalid ETH amount");

        Token memory token = tokens[_tokenId];

        uint256 amountToReceive = _calculateSwapAmount(0, _tokenId, msg.value, 18, token.decimal);

        // Update liquidity pool balances accordingly
        (uint256 token1Id, uint256 token2Id, , ) = _normalizePair(0, _tokenId, 0, 0);
        bytes32 pairId = keccak256(abi.encodePacked(token1Id, token2Id));
        require(poolExists[pairId], "Liquidity pool does not exist");
        LiquidityPool storage pool = pools[pairId];

        uint256 toTokenBalance = (_tokenId == pool.token1Id) ? pool.token1Balance : pool.token2Balance;
        require(toTokenBalance >= amountToReceive, "Insufficient liquidity");

        IERC20(token.tokenAddress).safeTransfer(msg.sender, amountToReceive);

        if (0 == pool.token1Id) {
            pool.token1Balance = pool.token1Balance + msg.value;
            pool.token2Balance = pool.token2Balance - amountToReceive;
        } else {
            pool.token1Balance = pool.token1Balance - amountToReceive;
            pool.token2Balance = pool.token2Balance + msg.value;
        }

        emit SwapExecuted(msg.sender, 0, _tokenId, msg.value, amountToReceive);
        return true;
    }

    // Token -> ETH
    function swapTokensForEth(uint256 _tokenId, uint256 _amountToSwap) external nonReentrant returns (bool) {
        require(_tokenId < tokenCount, "Invalid token ID");
        require(_tokenId != 0, "Cannot swap from ETH");
        require(_amountToSwap > 0, "Invalid token amount");

        Token memory token = tokens[_tokenId];

        require(IERC20(token.tokenAddress).allowance(msg.sender, address(this)) >= _amountToSwap, "Insufficient allowance");

        uint256 amountToReceive = _calculateSwapAmount(_tokenId, 0, _amountToSwap, token.decimal, 18);

        // Update liquidity pool balances accordingly
        (uint256 token1Id, uint256 token2Id, , ) = _normalizePair(_tokenId, 0, 0, 0);
        bytes32 pairId = keccak256(abi.encodePacked(token1Id, token2Id));
        require(poolExists[pairId], "Liquidity pool does not exist");
        LiquidityPool storage pool = pools[pairId];

        uint256 toTokenBalance = (0 == pool.token1Id) ? pool.token1Balance : pool.token2Balance;
        require(toTokenBalance >= amountToReceive, "Insufficient liquidity");

        IERC20(token.tokenAddress).safeTransferFrom(msg.sender, address(this), _amountToSwap);
        (bool success, ) = payable(msg.sender).call{value: amountToReceive}("");
        require(success, "ETH transfer failed");

        if (_tokenId == pool.token1Id) {
            pool.token1Balance = pool.token1Balance + _amountToSwap;
            pool.token2Balance = pool.token2Balance - amountToReceive;
        } else {
            pool.token1Balance = pool.token1Balance - amountToReceive;
            pool.token2Balance = pool.token2Balance + _amountToSwap;
        }

        emit SwapExecuted(msg.sender, _tokenId, 0, _amountToSwap, amountToReceive);
        return true;
    }

    // Add liquidity for pair (token IDs)
    // Accepts ETH for either side; msg.value must equal total ETH expected (token1Eth + token2Eth)
    function addLiquidity(
        uint256 _token1Id,
        uint256 _token2Id,
        uint256 _token1Amount,
        uint256 _token2Amount
    ) external payable onlyOwner {
        require(_token1Id < tokenCount && _token2Id < tokenCount, "Invalid token ID");
        require(_token1Id != _token2Id, "Cannot create pool with same token");
        require(_token1Amount > 0 && _token2Amount > 0, "Invalid amount");

        // Normalize tokens and amounts
        (uint256 token1Id, uint256 token2Id, uint256 amount1, uint256 amount2) = _normalizePair(
            _token1Id, _token2Id, _token1Amount, _token2Amount
        );

        bytes32 pairId = keccak256(abi.encodePacked(token1Id, token2Id));
        LiquidityPool storage pool = pools[pairId];

        // Calculate expected ETH amount
        uint256 expectedEth = 0;
        if (token1Id == 0) expectedEth += amount1;
        if (token2Id == 0) expectedEth += amount2;
        require(msg.value == expectedEth, "Incorrect ETH amount");

        // Transfer tokens if not ETH
        if (token1Id != 0) {
            IERC20(tokens[token1Id].tokenAddress).safeTransferFrom(msg.sender, address(this), amount1);
        }
        if (token2Id != 0) {
            IERC20(tokens[token2Id].tokenAddress).safeTransferFrom(msg.sender, address(this), amount2);
        }

        if (!poolExists[pairId]) {
            pool.token1Id = token1Id;
            pool.token2Id = token2Id;
            poolExists[pairId] = true;
        }

        pool.token1Balance = pool.token1Balance + amount1;
        pool.token2Balance = pool.token2Balance + amount2;

        emit LiquidityAdded(msg.sender, token1Id, token2Id, amount1, amount2);
    }

    // Remove all liquidity for pair
    function removeLiquidity(uint256 _token1Id, uint256 _token2Id) external nonReentrant onlyOwner {
        require(_token1Id < tokenCount && _token2Id < tokenCount, "Invalid token ID");

        // Normalize tokens
        (uint256 token1Id, uint256 token2Id, , ) = _normalizePair(_token1Id, _token2Id, 0, 0);

        bytes32 pairId = keccak256(abi.encodePacked(token1Id, token2Id));
        require(poolExists[pairId], "Liquidity pool does not exist");

        LiquidityPool storage pool = pools[pairId];
        uint256 token1Amount = pool.token1Balance;
        uint256 token2Amount = pool.token2Balance;

        require(token1Amount > 0 && token2Amount > 0, "No liquidity to remove");

        if (token1Id != 0) {
            IERC20(tokens[token1Id].tokenAddress).safeTransfer(msg.sender, token1Amount);
        } else {
            (bool success, ) = payable(msg.sender).call{value: token1Amount}("");
            require(success, "ETH transfer failed");
        }

        if (token2Id != 0) {
            IERC20(tokens[token2Id].tokenAddress).safeTransfer(msg.sender, token2Amount);
        } else {
            (bool success, ) = payable(msg.sender).call{value: token2Amount}("");
            require(success, "ETH transfer failed");
        }

        pool.token1Balance = 0;
        pool.token2Balance = 0;

        emit LiquidityRemoved(msg.sender, token1Id, token2Id, token1Amount, token2Amount);
    }

    // Owner can add a token record (no price feed here)
    function addToken(address _tokenAddress, uint256 _decimal, string memory _name) external onlyOwner {
        tokens[tokenCount] = Token(_tokenAddress, _decimal, _name);
        tokenPrice[tokenCount] = 0;
        tokenCount++;
    }

    receive() external payable {}
    fallback() external payable {}
}