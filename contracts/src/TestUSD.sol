// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Mock stablecoin for the Base Sepolia checkout demo. 6 decimals, like USDC,
/// so amount math in the app has to go through a real decimals-aware conversion instead
/// of defaulting to 18 and happening to work.
contract TestUSD is ERC20, Ownable2Step {
    uint256 public constant FAUCET_AMOUNT = 100 * 10 ** 6; // 100.00 tUSDC
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    mapping(address => uint256) public lastFaucetClaim;

    error FaucetOnCooldown(uint256 availableAt);

    constructor(address initialOwner) ERC20("Test USD", "tUSDC") Ownable(initialOwner) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Owner-controlled minting, for seeding balances (e.g. a seller demo wallet).
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Open faucet so a buyer with a fresh smart account can get test funds
    /// without asking anyone. Rate-limited per address so it isn't an unbounded free mint.
    function faucet() external {
        uint256 lastClaim = lastFaucetClaim[msg.sender];
        if (lastClaim != 0) {
            uint256 availableAt = lastClaim + FAUCET_COOLDOWN;
            if (block.timestamp < availableAt) revert FaucetOnCooldown(availableAt);
        }
        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
