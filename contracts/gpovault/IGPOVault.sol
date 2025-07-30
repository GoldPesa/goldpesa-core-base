// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
* @title IGPOVault
* @notice Interface for the GPOVault contract, used for staking GPO tokens and earning GPX rewards.
*/
interface IGPOVault {
    
    /// @notice Returns the total amount of GPO currently held inside the vault.
    function totalGPOInsideVault() external view returns (uint256);

    // ============================
    // ======= MAPPINGS ===========
    // ============================

    /**
    * @notice Returns raw staking metadata for a specific token ID.
    * @param _tokenId Token ID of the NFT.
    */
    function metadata(uint256 _tokenId) external view returns (
        uint256 id,
        uint256 gpoStaked,
        uint256 stakingDate,
        uint256 gpoBalance,
        uint256 gpxBalance
    );

    /**
    * @notice Daily GPX ecosystem value for a given UTC day.
    * @param day UTC timestamp at midnight.
    * @return Total GPX for the day.
    */
    function gpxEco(uint256 day) external view returns (uint256);

    /**
    * @notice Daily GPO ecosystem value for a given UTC day.
    * @param day UTC timestamp at midnight.
    * @return Total GPO for the day.
    */
    function gpoEco(uint256 day) external view returns (uint256);

    /**
    * @notice GPO amount staked by all users on a given day.
    * @param day UTC timestamp at midnight.
    * @return Amount of GPO staked.
    */
    function gpoStakedPerDay(uint256 day) external view returns (uint256);

    // ============================
    // ======= VIEW FUNCTIONS =====
    // ============================

    /**
    * @notice Returns the concatenated ABI-encoded metadata for all NFTs owned by a user.
    * @param _account Address of the NFT holder.
    * @return ABI-encoded `StakingMetadata[]`.
    */
    function tokensMetadata(address _account) external view returns (bytes memory);

    /**
    * @notice Returns the token URI metadata for a given NFT
    * @param _tokenId NFT ID
    */
    function tokenURI(uint256 _tokenId) external view returns (string memory);

    /**
    * @notice Simulates the current GPO and GPX balance of an NFT without changing state.
    * @param _tokenId Token ID of the staking NFT.
    * @return gpoBalance Remaining GPO.
    * @return gpxBalance Earned GPX.
    */
    function getStakeBalance(uint256 _tokenId) external view returns (uint256 gpoBalance, uint256 gpxBalance);
    
    /**
    * @notice Returns the max GPO currently available for conversion to GPX.
    * @return gpoStakedInsideVault GPO available for conversion.
    */
    function maxGPOAvailableForConversion() external view returns (uint256 gpoStakedInsideVault);
    
    // =============================
    // ======= CORE FUNCTIONS ======
    // =============================

    /**
    * @notice Stakes GPO and returns a staking NFT.
    * @param _account Address of the user.
    * @param _gpoAmount Amount of GPO to stake.
    * @return tokenId The ID of the NFT created or updated.
    */
    function stakeGPO(address _account, uint256 _gpoAmount) external returns (uint256 tokenId);

    /**
    * @notice Unstakes a staking NFT and distributes GPO and GPX rewards.
    * @param _tokenId Token ID of the NFT to unstake.
    */
    function unstakeNFT(uint256 _tokenId) external;
}

