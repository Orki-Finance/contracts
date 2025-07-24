// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MAX_ANNUAL_INTEREST_RATE, _1pct} from "src/Dependencies/Constants.sol";

contract ConstantsTest is Test {
    function test_maxInterestRate() public pure {
        assertEq(MAX_ANNUAL_INTEREST_RATE, _1pct * 350);
    }
}
