// SPDX-License-Identifier: MIT
// TEST FIXTURE — INTENTIONALLY DEFECTIVE. Local anvil only. Never deploy to a live network.
//
// Purpose: a minimal target carrying the assumed-distinctness defect (eval case-10) so the
// pipeline can be validated end to end without waiting on a historical fork. Every individual
// piece below is ordinary and correct-looking; the defect exists only when one reference is
// handed to two parameters written to assume they differ.
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract MockToken {
    string public name; uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    constructor(string memory n) { name = n; }
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal"); balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal"); require(allowance[f][msg.sender] >= a, "allow");
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract MiniAmm {
    mapping(address => uint256) public reserve;                     // token => pooled
    mapping(address => mapping(address => uint256)) public credit;  // user => token => claim

    function deposit(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        credit[msg.sender][token] += amount;
        reserve[token] += amount;
    }

    function withdraw(address token, uint256 amount) external {
        require(credit[msg.sender][token] >= amount, "insufficient credit");
        credit[msg.sender][token] -= amount;
        reserve[token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
    }

    function quote(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        uint256 rIn = reserve[tokenIn];
        uint256 rOut = reserve[tokenOut];
        require(rIn > 0 && rOut > 0, "no reserves");
        uint256 inWithFee = amountIn * 997;
        return (inWithFee * rOut) / (rIn * 1000 + inWithFee);   // constant product, 0.3% fee
    }

    // Correct for every input where tokenIn != tokenOut.
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 out) {
        uint256 cIn  = credit[msg.sender][tokenIn];
        uint256 cOut = credit[msg.sender][tokenOut];
        require(cIn >= amountIn, "insufficient credit");

        out = quote(tokenIn, tokenOut, amountIn);
        require(out > 0, "zero out");

        // Both writes are computed from the snapshots taken above.
        credit[msg.sender][tokenIn]  = cIn - amountIn;   // debit the input leg
        credit[msg.sender][tokenOut] = cOut + out;       // credit the output leg

        reserve[tokenIn]  += amountIn;
        reserve[tokenOut] -= out;
    }
}
