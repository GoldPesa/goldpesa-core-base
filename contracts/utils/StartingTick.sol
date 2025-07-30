// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

library StartingTick {
    using SafeCast for uint256;
    
    /**
     * @notice Computes a relative starting tick based on a target and current square root price.
     * @dev This function compares a target price level against a current reference price to derive
     *      a corresponding tick for initializing a pool or asset pairing.
     * @param targetTick Target tick representing the desired price level.
     * @param currentSqrtPriceQ96 Current square root price in Q64.96 format.
     * @return startingTick The computed tick corresponding to the implied price ratio.
     */
    function computeStartingTick(int24 targetTick, uint160 currentSqrtPriceQ96) internal pure returns (int24 startingTick) {
        // Calculate sqrt price at the target tick
        uint160 targetSqrtPriceQ96 = TickMath.getSqrtPriceAtTick(targetTick);

        // Compute squared prices in Q64.96 format
        uint256 targetSquared = FullMath.mulDiv(targetSqrtPriceQ96, targetSqrtPriceQ96, 1);
        uint256 currentSquared = FullMath.mulDiv(currentSqrtPriceQ96, currentSqrtPriceQ96, 1);

        // Compute the price ratio and convert to Q64.96 sqrt price
        uint256 ratio = FullMath.mulDiv(1 << 96, targetSquared, currentSquared);
        uint256 sqrtPriceQ96 = FullMath.mulDiv(Math.sqrt(ratio), 1 << 48, 1);

        // Convert the square root price to the nearest usable tick
        startingTick = TickMath.getTickAtSqrtPrice(sqrtPriceQ96.toUint160());
    }
}


   

