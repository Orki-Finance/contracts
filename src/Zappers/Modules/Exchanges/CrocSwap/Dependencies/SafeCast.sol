// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {

  /// @notice Cast a uint256 to a uint128, revert on overflow
  /// @param y The uint256 to be downcasted
  /// @return z The downcasted integer, now type uint128
  function toUint128(uint256 y) internal pure returns (uint128 z) {
    unchecked {
      // Explicit bounds check
      require((z = uint128(y)) == y);
    }
  }

}