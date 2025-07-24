// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "src/Interfaces/IPriceFeed.sol";

interface IPriceFeedMock is IPriceFeed {
    function setPrice(uint256 _price) external;
}
