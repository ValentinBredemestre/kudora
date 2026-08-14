// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice LOCALNET / E2E ONLY. This is not a production token.
contract MockUSDC {
    string public constant name = "Kudora Local Mock USDC";
    string public constant symbol = "MockUSDC";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 supply) {
        totalSupply = supply;
        balanceOf[msg.sender] = supply;
        emit Transfer(address(0), msg.sender, supply);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "allowance");
        allowance[from][msg.sender] = allowed - value;
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "zero address");
        require(balanceOf[from] >= value, "balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}

interface ILocalMockUSDC {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice LOCALNET / E2E ONLY. One constant-product KUD/MockUSDC fixture.
contract LocalSwapRouter {
    ILocalMockUSDC public immutable token;

    event Swap(address indexed account, uint256 kudIn, uint256 tokenOut);

    constructor(address tokenAddress) {
        token = ILocalMockUSDC(tokenAddress);
    }

    function seed() external payable {}

    function getAmountOut(uint256 kudIn) public view returns (uint256) {
        uint256 kudReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        require(kudIn > 0 && kudReserve > 0 && tokenReserve > 0, "empty pool");
        return (tokenReserve * kudIn) / (kudReserve + kudIn);
    }

    function swapExactKUDForUSDC(uint256 minimumOut) external payable returns (uint256 amountOut) {
        uint256 kudReserveBefore = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        require(msg.value > 0 && kudReserveBefore > 0 && tokenReserve > 0, "empty pool");
        amountOut = (tokenReserve * msg.value) / (kudReserveBefore + msg.value);
        require(amountOut >= minimumOut, "slippage");
        require(token.transfer(msg.sender, amountOut), "transfer");
        emit Swap(msg.sender, msg.value, amountOut);
    }
}
