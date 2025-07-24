// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for the CL Factory
/// @notice The CL Factory facilitates creation of CL pools and control over the protocol fees
interface ICLFactory {
    /// @notice Creates a pool for the given two tokens and tick spacing
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param tickSpacing The desired tick spacing for the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool, as a Q64.96
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. The call will
    /// revert if the pool already exists, the tick spacing is invalid, or the token arguments are invalid
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96)
        external
        returns (address pool);

    function getPool(address tokenA, address tokenB, int24 tickSpacing) external returns (address);

    function tickSpacingToFee(int24) external returns (uint24);
}
