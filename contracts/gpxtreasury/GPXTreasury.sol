// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title GPXTreasury
 * @notice A secure treasury contract that holds ERC20 tokens
 * @dev Uses OpenZeppelin’s Ownable2Step for secure ownership management.
 */
contract GPXTreasury is Ownable2Step {
    using SafeERC20 for IERC20;

    // ============================
    // ========= EVENTS ===========
    // ============================

    /**
     * @notice Emitted when the treasury transfers ERC20 tokens to the owner.
     * @param owner The address of the owner receiving the tokens
     * @param token The address of the ERC20 token contract.
     * @param amount The amount of ERC20 tokens transferred.
     */
    event TreasuryTransfer(address indexed owner, address indexed token, uint256 amount);

    // ============================
    // ======== CONSTRUCTOR =======
    // ============================

    constructor(address _multiSigWallet) Ownable(_multiSigWallet) {}

    /**
     * @dev Transfer ERC20 tokens from Treasury to the owner.
     * 
     * @param token ERC20 token address
     * @param amount Transfer amount
     *
     */
    function transferTokens(address token, uint256 amount) external onlyOwner { 
         require(amount > 0, "Amount must be greater than zero");
         IERC20(token).safeTransfer(owner(), amount);
         emit TreasuryTransfer(owner(), token, amount);
    }
    
    // ============================
    // ======= ETH GUARD ==========
    // ============================

    /**
     * @dev Fallback function to ensure ETH is never accepted.
     */
    receive() external payable {
        revert("ETH not accepted");
    }

    /**
     * @dev Fallback function to ensure ETH with data is never accepted.
     */
    fallback() external payable {
        revert("ETH not accepted");
    }
}