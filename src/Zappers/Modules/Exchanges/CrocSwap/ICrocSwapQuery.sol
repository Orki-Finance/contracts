// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Dependencies/CurveMath.sol";

interface ICrocSwapQuery {

    /* @notice Queries and returns the current price of the pool's curve
     * 
     * @param base The base token address
     * @param quote The quote token address
     * @param poolIdx The pool index
     *
     * @return Q64.64 square root price of the pool */
    function queryPrice (address base, address quote, uint256 poolIdx)
        external view returns (uint128);

    /* @notice Queries and returns the total liquidity currently active on the pool's curve
     * 
     * @param base The base token address
     * @param quote The quote token address
     * @param poolIdx The pool index
     *
     * @return The total sqrt(X*Y) liquidity currently active in the pool */
    function queryLiquidity (address base, address quote, uint256 poolIdx)
        external view returns (uint128);

    /* @notice Queries and returns the surplus collateral of a specific token held by
     *         a specific address.
     *
     * @param owner The address of the owner of the surplus collateral
     * @param token The address of the token balance being queried.
     *
     * @return The total amount of surplus collateral held by this owner in this token.
     *         0 if none. */
    function querySurplus (address owner, address token)
        external view returns (uint128 surplus);

    /* @notice Queries and returns the current state of a liquidity curve for a given pool.
     * 
     * @param base The base token address
     * @param quote The quote token address
     * @param poolIdx The pool index
     *
     * @return The CurveState struct of the underlying pool. */
    function queryCurve (address base, address quote, uint256 poolIdx)
        external view returns (CurveMath.CurveState memory curve);

}