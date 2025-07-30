// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { GPMTreasury } from "./GPMTreasury.sol";
import { GPXOwner } from "../gpxowner/GPXOwner.sol";

/**
 * @title IGoldPesaMines
 * @notice Interface for the GoldPesa Mines contract.
 */
interface IGoldPesaMines {

    // =================================
    // ========== CONSTANTS ============
    // =================================

    /// @notice Returns the maximum level in the mine
    function MAX_LEVEL() external pure returns (int8);

    // ============================
    // ======= MAPPINGS ===========
    // ============================

    /// @notice Returns the MiningNFT metadata for a given token ID.
    /// @param tokenId       The NFT ID to query.
    /// @return id           The unique NFT ID.
    /// @return positionList The index of the NFT within its current level’s list.
    /// @return currentLevel The current level of this miner.
    /// @return gpxBalance   The GPX staking balance allocated to this miner.
    function metadata(uint256 tokenId)
        external
        view
        returns (
            uint256 id,
            uint256 positionList,
            int8 currentLevel,
            uint256 gpxBalance
        );

    // ============================
    // ======= VIEW FUNCTIONS =====
    // ============================

    /**
     * @notice Returns the combined GPX balance (original stake + current level reward) for a given NFT.
     * @param tokenId The ID of the GoldPesa Miner NFT to query.
     * @return totalGPX The sum of the NFT’s stored `gpxBalance` and its level-based reward.
     */
    function getTotalGPXBalance(uint256 tokenId) external view returns (uint256 totalGPX);

    /**
     * @notice Calculates the GPX reward allocated to each miner at a specific level.
     * @dev Divides the contract’s available GPX prize pool equally across all levels, 
     *      then splits that level’s share among its current miners.
     * @param level The target level in the GoldPesa Mine (0 ≤ level < MAX_LEVEL).
     * @return rewardGPX The amount of GPX rewards each miner at the specified `level` will receive.
     */
    function gpxTotalPrizeAt(int8 level) external view returns (uint256 rewardGPX);

    /**
     * @notice Returns the metadata URI for a given NFT.
     * @dev Conforms to the ERC-721 `tokenURI` spec. The URI is constructed dynamically  
     *      on-chain based on the miner’s level and GPX balance.
     * @param tokenId The ID of the GoldPesa Miner NFT.
     * @return string A string representing the token’s metadata URI.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /**
     * @notice Retrieves the current number of miners at each level of the GoldPesa Mine.
     * @dev Returns a fixed-size array of length 16, where index i corresponds to level i.
     * @return counts A `uint256[16]` array where `counts[i]` is the number of miners at level `i`.
     */
    function getCountPlayers() external view returns (uint256[16] memory counts);

    /**
     * @notice Retrieves ABI-encoded metadata for all NFTs owned by a specific address.
     * @dev Loops through `balanceOf(account)` tokens and concatenates each `MiningNFT` struct 
     *      (id, currentLevel, gpxBalance) via `abi.encodePacked`. 
     *      Consumers must decode the returned bytes in sequence to recover each struct.
     * @param account The address whose NFT metadata should be returned.
     * @return bytes Dynamic `bytes` array containing the ABI-encoded `MiningNFT` structs 
     *               for each token ID owned by `account`.
     */
    function tokensMetadata(address account) external view returns (bytes memory);

    /**
     * @notice Returns the total number of NFTs currently queued for ascension processing.
     * @dev Calls `tokensQueue.length()` on the internal queue structure to report how many 
     *      miners are pending placement into levels.
     * @return uint256 Total count of queued token IDs awaiting ascension.
     */
    function tokensQueueLength() external view returns (uint256);

    /**
     * @notice Indicates whether there are any NFTs waiting in the ascension queue.
     * @dev Returns true if `tokensQueueLength()` > 0, signaling that an automated on-chain 
     *      process (e.g., calling `processAscensions`) should be triggered.
     * @return bool True if one or more token IDs are queued for ascension; otherwise false.
     */
    function needsAutomation() external view returns (bool);

    /// @notice Get the current VRF coordinator owner
    function owner() external view returns (address);

    // =============================
    // ======= CORE FUNCTIONS ======
    // =============================

    /// @notice Processes queued NFTs, inserting them into the mine.
    /// @param maxIter The maximum number of Gold Miners to process in this call (to avoid block gas limit issues).
    function processAscensions(uint256 maxIter) external;

    /// @notice Allows VRF owner to begin transferring ownership to a new address.
    /// @param to The address to transfer ownership to.
    function transferOwnership(address to) external;

    /// @notice Allows an ownership transfer to be completed by the recipient.
    function acceptOwnership() external;
}
