// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {CurrencyLibrary, Currency, equals} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {GPO} from "./GPO.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {TokenFactory} from "../utils/TokenFactory.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {GPOOwner} from "../gpoowner/GPOOwner.sol";

/**
 * @title GPOHooks — GoldPesa Option Uniswap V4 Hook Contract
 * @notice This contract implements custom Uniswap V4 Hooks for the GoldPesa Option (GPO) token.
 *
 * @dev
 * - GPOHooks is a fully decentralized, ownerless, and immutable smart contract that extends the functionality of Uniswap V4
 *   via hook-based logic. It programmatically enforces fee collection in USDC, locks liquidity once initialized,
 *   and restricts unauthorized operations like removing liquidity.
 *
 * Key Features:
 * - Hook-Powered DeFi Automation: Uses Uniswap V4 hook callbacks to apply GPO-specific logic during liquidity and swap events.
 * - Token Deployment: Deploys the GPO ERC-20 token and ensures it's paired with USDC using `deployToken0` to maintain ordering.
 * - Liquidity Initialization: Mints the entire GPO token supply into a Uniswap V4 position with the full range [-276324, MAX_TICK].
 * - Permanent Liquidity Lock: Prevents liquidity from being removed after initial minting.
 * - USDC Fee on Swap: Imposes a 10% USDC fee on every swap and routes the collected fees to the GPO Owner.
 *
 * Security Notes:
 * - No owner functions exist. This contract is self-governing once deployed.
 * - ETH is explicitly rejected using `receive()` and `fallback()` functions.
 * - All liquidity management operations are guarded by modifiers to ensure one-time execution.
 *
 */
contract GPOHooks is BaseHook, TokenFactory {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using SafeCast for uint256;

    // =======================
    // ======= ERRORS ========
    // =======================

    /// @notice Thrown when liquidity is added from a source other than the Hook.
    error OnlyHookCanAddLiquidity();
    /// @notice Thrown when a non-authorized address attempts to initialize the pool
    error UnauthorizedPoolInitialization();
    /// @notice Thrown when an attempt to add/remove liquidity is made while liquidity is locked
    error LiquidityLockedForever();
    /// @notice Thrown when an attempt is made to send tokens to the pool without a valid swap or mint context
    error DonationsNotAllowed();

    // =======================
    // ======= EVENTS ========
    // =======================

    /// @notice Emitted when a USDC fee is collected and sent to the GPO Owner
    /// @param gpoOwnerAddress The address of the owner of GPO receiving the fee
    /// @param feeAmount The amount of USDC collected and distributed as a fee
    event UsdcFeeCollected(address indexed gpoOwnerAddress, uint256 feeAmount);

    // =================================
    // ========== CONSTANTS ============
    // =================================

    /// @notice Fee on Swap (%)
    uint256 public constant FEE_ON_SWAP_PERCENT = 10;
    /// @notice GPO Total Supply
    uint256 public constant GPO_TOTAL_SUPPLY = 100_000_000 * 10**18;
    /// @dev No Hook Data
    bytes internal constant ZERO_BYTES = bytes("");
    /// @dev Starting Tick Price (1 GPO (1e18) = 1 USDC (1e6))
    int24 public constant startingTick = -276324;

    // =================================
    // ======= PUBLIC STATE GETTERS ====
    // =================================

    /// @dev Permit2 address
    address public immutable permit2;

    /// @notice Uniswap V4 IPoolManager defined in BaseHook as poolManager

    /// @notice Uniswap V4 Position Manager
    IPositionManager public immutable positionManager;
    /// @notice GPO Currency
    Currency public immutable gpo;
    /// @notice USDC Currency
    Currency public immutable usdc;
    /// @notice GPO Owner Contract
    GPOOwner public immutable gpoOwner;
    /// @notice GPO Pool Key
    PoolKey public gpoPoolKey;

    /// @notice Liquidity Locked Flag
    bool public liquidityLocked;
    /// @notice Current Position ID
    uint256 public positionId;

    // =================================
    // ==== PRIVATE STATE VARIABLES ====
    // =================================

    // Deployer address, used for one-time setup operations
    address private immutable deployer;
    /// @dev Flag which only allows the hook to rebalance liquidity
    bool private isRebalancing;

    // =================================
    // ========== MODIFIERS ============
    // =================================

    /// @notice Liquidity Not Locked Modifier
    modifier liquidityNotLocked() {
        if (liquidityLocked) revert LiquidityLockedForever();
        _;
    }

    // ============================
    // ======== CONSTRUCTOR =======
    // ============================

    /**
     * @dev Initializes the GPOHooks contract
     *
     * @param _poolManager Uniswap V4 Pool Manager address
     * @param _positionManager Uniswap V4 Position Manager address
     * @param _usdc USDC token address
     * @param _multiSigWalletGPOOwner GPO Owner contract address
     * @param _permit2 Permit2 address for token approvals
     * @param _deployer Deployer address for one-time setup operations
     */
    constructor(
        address _poolManager,
        address _positionManager, 
        address _usdc,
        address _multiSigWalletGPOOwner,
        address _permit2,
        address _deployer
    ) payable BaseHook(IPoolManager(_poolManager)) TokenFactory(_usdc) {
        // Ensure the deployer is set
        deployer = _deployer;

        positionManager = IPositionManager(_positionManager);
        usdc = Currency.wrap(_usdc);
        permit2 = _permit2;

        // Get GPO bytecode
        bytes memory gpoBytecode = type(GPO).creationCode;

        // Deploy the GPO contract using deployToken0 ensuring gpo (currency0) < usdc (currency1)
        address _gpo = deployToken0(gpoBytecode);
        gpo = Currency.wrap(_gpo);

        // Safety Check to make sure that GPO address is less than USDC
        require(_gpo < _usdc, "GPO address is not less than USDC address");

        // Deploy GPOOwner contract
        gpoOwner = new GPOOwner(_multiSigWalletGPOOwner);

        // Configure the Pool
        gpoPoolKey = PoolKey({
            currency0: gpo,
            currency1: usdc,
            fee: 0,
            tickSpacing: 1,
            hooks: IHooks(address(this))
        });

        // Initializes the pool with the given initial square root price
        poolManager.initialize(gpoPoolKey, TickMath.getSqrtPriceAtTick(startingTick));
    }

    // ============================
    // ======= MAIN FUNCTION ======
    // ============================

    /**
     * @notice Mints a Uniswap V4 liquidity position using the full GPO balance held by this contract.
     * @dev 
     *      - This function is only callable if liquidity is not permanently locked (`liquidityNotLocked` modifier).
     *      - It ensures the contract holds the entire GPO total supply before proceeding.
     *      - Computes liquidity units for the range [-276324, MAX_TICK] based on the total GPO balance.
     * 
     * @custom:warning This function assumes that the full GPO total supply is available within the contract and will revert if not.
     * @custom:security Only call this once during setup; subsequent calls will revert.
     */
    function mintLiquidity() external liquidityNotLocked {
        // Ensure the caller is the deployer
        require(msg.sender == deployer, "Only deployer can mint liquidity");
        
        // 1. Get total balance of GPO inside this contract
        uint256 gpoTotalBalance = IERC20(Currency.unwrap(gpo)).balanceOf(address(this));

        // 2. Safety check to make sure GPO's total supply is in this contract
        require(gpoTotalBalance == GPO_TOTAL_SUPPLY, "Total GPO supply is not available");

        // 3. Converts token0 amount to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(startingTick),
                TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK), 
                gpoTotalBalance
        );

        // 4. Prepare action sequence: MINT_POSITION → SETTLE_PAIR
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), 
            uint8(Actions.SETTLE_PAIR)
        );

        // 5. Prepare Action parameters
        bytes[] memory params = new bytes[](2);

        // 6. Encode the MINT_POSITION parameters
        params[0] = abi.encode(
            gpoPoolKey, 
            startingTick, 
            TickMath.MAX_TICK, 
            liquidity,
            gpoTotalBalance.toUint128(), 
            0, // no USDC amount
            address(this),
            ZERO_BYTES
        );

        // 7. Encode the SETTLE_PAIR parameters
        params[1] = abi.encode(gpoPoolKey.currency0, gpoPoolKey.currency1);

        // 8. Approve token transfers via Permit2 and PositionManager
        IERC20(Currency.unwrap(gpo)).approve(permit2, gpoTotalBalance);
        IAllowanceTransfer(permit2).approve(
            Currency.unwrap(gpo), 
            address(positionManager), 
            gpoTotalBalance.toUint160(), 
            type(uint48).max
        );

        // 9. Execute the multicall to mint and settle the liquidity
        uint256 deadline = block.timestamp + 300;
        isRebalancing = true;
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            deadline
        );
        isRebalancing = false;

        // 10. Store the position ID 
        positionId = positionManager.nextTokenId() - 1;
    }

    /**
     * Defines the Uniswap V4 hooks utilized in our implementation, specifying the exact address where our contract
     * must be deployed for Uniswap V4 compatibility.
     *
     * @dev 0010 1110 1110 1100 == 2EEC
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /**
     * This hook is triggered before a pool's state is initialized, ensuring that external contracts
     * cannot initialize pools using our contract as a hook.
     *
     * @dev Since `poolManager.initialize` is called directly from the constructor, this hook
     *      is bypassed, effectively circumventing the restriction initially. 
     */
    function beforeInitialize(
        address, 
        PoolKey calldata, 
        uint160
    ) external view override onlyPoolManager returns (bytes4) {
        revert UnauthorizedPoolInitialization();
    }

    /// @inheritdoc IHooks
    /// @dev Prevents any add‐liquidity call while `liquidityLocked` is true.
    function beforeAddLiquidity(
        address, 
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        if (liquidityLocked) revert LiquidityLockedForever();
        if (!isRebalancing) revert OnlyHookCanAddLiquidity();
        return this.beforeAddLiquidity.selector;
    }

    /// @inheritdoc IHooks
    /// @dev Sets the `liquidityLocked` flag to true after the first liquidity addition,
    ///      preventing any further modifications to the pool's liquidity.
    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager() returns (bytes4, BalanceDelta) {
        liquidityLocked = true;
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @inheritdoc IHooks
    /// @dev Reverts to ensure that liquidity is permanently locked in the pool.
    ///      Safety net even though the position NFT is in custody of this ownerless contract.
    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        revert LiquidityLockedForever();
    }

    /// @inheritdoc IHooks
    /// @dev Disable all external donations
    function beforeDonate(
        address, 
        PoolKey calldata, 
        uint256, uint256, 
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        revert DonationsNotAllowed();
    }

    /**
     * @notice Hook executed before each swap in the GPO liquidity pool.
     *
     * @param key The PoolKey representing the Uniswap V4 pool involved in the swap.
     * @param params Swap parameters including direction and amount specified.
     *
     * @return selector The function selector for `beforeSwap`.
     * @return returnDelta The amount of fee to deduct in this swap.
     * @return hookData A reserved uint24 value (unused, set to 0).
     */
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        // Determine if the swap is exact input or exact output
        bool exactInput = params.amountSpecified < 0;

        // Determine the swap fee currency based on swap parameters - GPO (currency0) or USDC (currency1)
        Currency beforeSwapFeeCurrency = exactInput == params.zeroForOne
            ? key.currency0
            : key.currency1;

        // New BeforeSwapDelta must be returned, so store in memory
        BeforeSwapDelta returnDelta;

        // Take the fee in USDC from poolManager and distribute to the GPO Owner
        if (beforeSwapFeeCurrency == usdc) {
            // Get the positive amount (specified amount)
            uint256 usdcAmount = exactInput
                ? uint256(-params.amountSpecified)
                : uint256(params.amountSpecified);
            
            // Calculate the Fee Amount
            uint256 feeAmount = exactInput 
                ? (usdcAmount * FEE_ON_SWAP_PERCENT) / 100 
                : (usdcAmount * FEE_ON_SWAP_PERCENT) / (100 - FEE_ON_SWAP_PERCENT);
            
            // Get the poolManager's USDC balance
            uint256 usdcPoolBalance = IERC20(Currency.unwrap(usdc)).balanceOf(address(poolManager));

            // Ensure there is enough USDC inside the pool to take the fee
            if (usdcPoolBalance >= feeAmount) {
                // Take the fee in USDC from poolManager and distribute to GPO Owner 
                usdc.take(poolManager, gpoOwner.owner(), feeAmount, false);

                // Emit USDC Fee Distributed event
                emit UsdcFeeCollected(gpoOwner.owner(), feeAmount);

                // At this stage USDC is the specified amount regardless of exact input or output
                returnDelta = toBeforeSwapDelta(feeAmount.toInt128(), 0);
            }
        }

        return (this.beforeSwap.selector, returnDelta, 0);
    }

    /**
     * @notice Hook executed after each swap in the GPO liquidity pool.
     *
     * @param key PoolKey identifying the pool.
     * @param params Swap parameters containing direction and amount.
     * @param delta Change in token balances resulting from the swap.
     *
     * @return selector The function selector for `afterSwap`.
     * @return zDelta The amount charged as protocol fee (in the unspecified currency).
     */
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // Determine if the swap is exact input or exact output
        bool exactInput = params.amountSpecified < 0;

        // Determine the swap fee currency based on swap parameters - GPO (currency0) or USDC (currency1)
        Currency afterSwapFeeCurrency = exactInput == params.zeroForOne
            ? key.currency1
            : key.currency0;

        // New zDelta must be returned, so store in memory
        int128 zDelta = 0;

        // Extract swap token delta for Token1
        int128 amount1 = delta.amount1();

        if (afterSwapFeeCurrency == usdc) {
            // Get the positive USDC amount (unspecified amount)
            uint256 usdcAmount = exactInput
                ? uint256(uint128(amount1)) // amount1 is positive
                : uint256(uint128(-amount1)); // Convert to positive int128 first, then uint256

            // Calculate the Fee Amount
            uint256 feeAmount = exactInput 
                ? (usdcAmount * FEE_ON_SWAP_PERCENT) / 100 
                : (usdcAmount * FEE_ON_SWAP_PERCENT) / (100 - FEE_ON_SWAP_PERCENT);

            // Get the poolManager's USDC balance
            uint256 usdcPoolBalance = IERC20(Currency.unwrap(usdc)).balanceOf(address(poolManager));

            // Ensure there is enough USDC inside the pool to take the fee
            if (usdcPoolBalance >= feeAmount) {
                // Take the fee in USDC from poolManager and distribute to GPO Owner 
                usdc.take(poolManager, gpoOwner.owner(), feeAmount, false);

                // Emit USDC Fee Distributed event
                emit UsdcFeeCollected(gpoOwner.owner(), feeAmount);

                // Set zDelta (USDC = unspecified currency) to the fee amount 
                zDelta = feeAmount.toInt128();
            }
        }

        return (this.afterSwap.selector, zDelta);
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
