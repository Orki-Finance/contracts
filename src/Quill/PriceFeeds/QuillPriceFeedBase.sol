// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../../PriceFeeds/MainnetPriceFeedBase.sol";
import "openzeppelin-contracts/contracts/access/manager/AccessManaged.sol";

abstract contract QuillPriceFeedBase is MainnetPriceFeedBase {
    constructor(address _authority, address _ethUsdOracleAddress, uint256 _ethUsdStalenessThreshold)
        MainnetPriceFeedBase(_authority, _ethUsdOracleAddress, _ethUsdStalenessThreshold)
    {}
}
