// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IGPMtreasury
 * @notice Interface for the GoldPesa Mines Treasury contract.
 */
interface IGPMTreasury {

    // =================================
    // ========== CONSTANTS ============
    // =================================

    /// @notice GoldPesa Miner NFT fixed price = $10 USDC (6 decimals)
    function NFT_PRICE_IN_USDC() external view returns (uint256);
    /// @notice GoldPesa Miner NFT fixed fee = $1 USDC (6 decimals)
    function NFT_FEE_IN_USDC() external view returns (uint256);

    // ============================
    // ======= VIEW FUNCTIONS =====
    // ============================

    /**
     * @notice Calculates the total net earnings held by the mine contract in GPX and USDC
     * @dev This includes only net GPX earnings inside the mine contract excluding staked GPX
     * @return totalMineEarningsInGPX The total earnings inside the mine.
     * @return totalMineEarningsInUSDC The total USDC-equivalent value (6 decimals) of the GPX earnings held by the mine.
     */
    function getTotalMineEarnings() external view returns (uint256 totalMineEarningsInGPX, uint256 totalMineEarningsInUSDC);
   
    /**
     * @notice Calculates the total value of all GPX tokens held by the mine contract in GPX and USDC
     * @dev This includes all GPX staked and GPX earnings inside the mine contract.
     * @return totalMineValueInGPX The total GPX inside the mine.
     * @return totalMineValueInUSDC The total USDC-equivalent value (6 decimals) of the GPX held by the mine.
     */
    function getTotalMineValue() external view returns (uint256 totalMineValueInGPX, uint256 totalMineValueInUSDC);

    /**
    * @notice Calculates the total USDC-equivalent value of an individual NFT's GPX balance.
    * @param tokenId NFT ID to query.
    * @return totalNFTValueInUSDC The USDC value (6 decimals) of that NFT’s GPX holdings.
    */
    function getTotalNFTValueInUSDC(uint256 tokenId) external view returns (uint256 totalNFTValueInUSDC);

    /**
    * @notice Converts a given GPX amount into its USDC-equivalent value using current Uniswap price.
    * @param gpxAmount Amount of GPX (18 decimals) to convert.
    * @return usdcValue Equivalent USDC value (6 decimals).
    */
    function getGPXValueInUSDC(uint256 gpxAmount) external view returns (uint256 usdcValue);

    // =============================
    // ======= CORE FUNCTIONS ======
    // =============================

    /**
    * @notice Purchase GoldPesa Miner NFTs using a signed permit (ERC-2612).
    * @dev Allows `msg.sender` to approve this contract to spend their `tokenIn` off-chain, then
    *      execute the purchase and mint in a single transaction.
    * @param amountInMaximum The maximum amount of `tokenIn` the buyer is willing to spend.
    * @param tokenIn         The ERC-20 token address used for payment
    * @param poolFee         The Uniswap V3 pool fee tier (e.g., 3000 for 0.3%) when swapping `tokenIn` → USDC (if needed).
    * @param deadline        The Unix timestamp by which the permit signature and swaps must complete.
    * @param account         The recipient address that will receive the newly minted NFTs.
    * @param quantity        The number of NFTs to purchase and mint.
    * @param v               The `v` component of the ERC-2612 permit signature.
    * @param r               The `r` component of the ERC-2612 permit signature.
    * @param s               The `s` component of the ERC-2612 permit signature.
    * @return amountIn   The actual amount of `tokenIn` consumed by this transaction
    * @return gpxStaked  The net amount of GPX used to stake (after subtracting any bonus or fee).
    * @return ids        An array of newly minted NFT IDs.
    */
    function buyNFTSig(
        uint256 amountInMaximum,
        address tokenIn,
        uint24 poolFee,
        uint256 deadline,
        address account,
        uint256 quantity,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountIn, uint256 gpxStaked, uint256[] memory ids);

    /**
    * @notice Purchase GoldPesa Miner NFTs using any supported token or native ETH.
    * @dev
    *  - If `tokenIn == address(0)`, treats `msg.value` as ETH, wraps it into WETH, and uses WETH as payment.
    *  - If `tokenIn` is an ERC-20 (including GPX or USDC), performs the necessary transfers and swaps,
    *    then stakes the resulting GPX to mint NFTs.
    * @param amountInMaximum The maximum amount of `tokenIn` (or WETH) the buyer is willing to spend.
    *                        If paying with ETH, send it as `msg.value` and set `tokenIn == address(0)`.
    * @param tokenIn         The input token’s address. Use `address(0)` to pay in native ETH (wrapped to WETH internally).
    * @param poolFee         The Uniswap V3 pool fee tier (e.g., 3000 for 0.3%) when swapping `tokenIn` → USDC (if needed).
    * @param deadline        The Unix timestamp by which all on-chain operations (especially swaps) must complete.
    *                        If set to 0, defaults to `block.timestamp + 300`.
    * @param account         The recipient address that will receive the newly minted NFTs.
    * @param quantity        The number of GoldPesa Miner NFTs to purchase.
    * @return amountIn   The actual amount of `tokenIn` (or WETH/ETH) consumed by this transaction (before any refund).
    * @return gpxStaked  The net amount of GPX used to stake (after subtracting any bonus or fee).
    * @return ids        An array of newly minted NFT IDs, in order of minting.
    */
    function buyNFT(
        uint256 amountInMaximum,
        address tokenIn,
        uint24 poolFee,
        uint256 deadline,
        address account,
        uint256 quantity
    ) external payable returns (uint256 amountIn, uint256 gpxStaked, uint256[] memory ids);

    /**
    * @notice Redeem all accumulated GPX rewards for a specific GoldPesa Miner NFT and burn it.
    * @dev
    *  - Verifies that `msg.sender` owns `tokenId`.
    *  - Approves this contract to burn the NFT via `unsafeApprove`.
    *  - Removes the NFT from its current level queue, transfers total GPX (stake + level prizes) to the owner, and burns the NFT.
    * @param tokenId The ID of the GoldPesa Miner NFT to cash out.
    */
    function cashOut(uint256 tokenId) external;

    /**
    * @notice Returns a GPX quote for purchasing a given number of GoldPesa Miner NFTs.
    * @dev
    *  - Computes the total USDC needed for `quantity` NFTs (price + fee).
    *  - Uses the Uniswap V4 Quoter to determine how much GPX would be required to swap exactly that USDC amount.
    * @param quantity The number of NFTs to purchase.
    * @return gpxAmount Estimated amount of GPX required to cover both price and fee for `quantity` NFTs.
    */
    function getQuote(uint256 quantity) external returns (uint256 gpxAmount);
}
