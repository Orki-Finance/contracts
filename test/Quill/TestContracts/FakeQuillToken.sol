// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import {BoldToken} from "src/BoldToken.sol";

// an override of the BoldToken contract to explicitly use mock names
contract FakeQuillToken is BoldToken {
    string internal constant TEST_NAME = "not a real token";
    string internal constant TEST_SYMBOL = "NOT REAL";

    function initialize(address _authority) public override initializer {
        __ERC20_init(TEST_NAME, TEST_SYMBOL);
        __ERC20Permit_init(TEST_NAME);
        __QuillUUPSUpgradeable_init(_authority);
    }
}
