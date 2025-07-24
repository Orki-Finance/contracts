// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract RedStoneAgg {

    // eth usd mock data feed id 
    bytes32 constant ETH_USD_FEEDID=0x4554480000000000000000000000000000000000000000000000000000000000;
    bytes32 constant RSWETH_ETH_FEEDID=0x7273774554485f46554e44414d454e54414c0000000000000000000000000000;
    bytes32 constant WEETH_ETH_FEEDID=0x77654554485f46554e44414d454e54414c000000000000000000000000000000;
    bytes32 constant SWELL_USD_FEEDID=0x5357454c4c000000000000000000000000000000000000000000000000000000;
    bytes32 constant SWETH_ETH_FEEDID=0x73774554485f46554e44414d454e54414c000000000000000000000000000000;

    // lastDataTimestamp (uint256) : 1744014676000
    // lastBlockTimestamp (uint256) : 1744014681
    // lastValue (uint256) : 148346073672

    constructor() {
        
    }

    event ValueUpdate(uint256 value, bytes32 dataFeedId, uint256 updatedAt);

    uint256 private ethusdLastDataTimestamp;
    uint256 private ethusdLastBlockTimestamp;
    uint256 private ethusdLastValue;
    uint256 private rswethethLastDataTimestamp;
    uint256 private rswethethLastBlockTimestamp;
    uint256 private rswethethLastValue;
    uint256 private weethethLastDataTimestamp;
    uint256 private weethethLastBlockTimestamp;
    uint256 private weethethLastValue;
    uint256 private swellusdLastDataTimestamp;
    uint256 private swellusdLastBlockTimestamp;
    uint256 private swellusdLastValue;
    uint256 private swethLastDataTimestamp;
    uint256 private swethLastBlockTimestamp;
    uint256 private swethLastValue;

    function getLastUpdateDetails(bytes32 dataFeedId) external view returns (uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue) {
        uint256 currentTimestamp = block.timestamp;
        if (dataFeedId == ETH_USD_FEEDID) {
            return (currentTimestamp, currentTimestamp, ethusdLastValue);
        } else if (dataFeedId == RSWETH_ETH_FEEDID) {
            return (currentTimestamp, currentTimestamp, rswethethLastValue);
        } else if (dataFeedId == WEETH_ETH_FEEDID) {
            return (currentTimestamp, currentTimestamp, weethethLastValue);
        } else if (dataFeedId == SWELL_USD_FEEDID) {
            return (currentTimestamp, currentTimestamp, swellusdLastValue);
        } else if (dataFeedId == SWETH_ETH_FEEDID) {
            return (currentTimestamp, currentTimestamp, swethLastValue);
        } else {
            revert("Invalid data feed ID");
        }
    }

    function updateDataFeed(bytes32 dataFeedId, uint256 newValue) external {
        uint256 currentTimestamp = block.timestamp;
        if (dataFeedId == ETH_USD_FEEDID) {
            ethusdLastDataTimestamp = currentTimestamp;
            ethusdLastBlockTimestamp = block.number;
            ethusdLastValue = newValue;
        } else if (dataFeedId == RSWETH_ETH_FEEDID) {
            rswethethLastDataTimestamp = currentTimestamp;
            rswethethLastBlockTimestamp = block.number;
            rswethethLastValue = newValue;
        } else if (dataFeedId == WEETH_ETH_FEEDID) {
            weethethLastDataTimestamp = currentTimestamp;
            weethethLastBlockTimestamp = block.number;
            weethethLastValue = newValue;
        } else if (dataFeedId == SWELL_USD_FEEDID) {
            swellusdLastDataTimestamp = currentTimestamp;
            swellusdLastBlockTimestamp = block.number;
            swellusdLastValue = newValue;
        } else if (dataFeedId == SWETH_ETH_FEEDID) {
            swethLastDataTimestamp = currentTimestamp;
            swethLastBlockTimestamp = block.number;
            swethLastValue = newValue;
        } else {
            revert("Invalid data feed ID");
        }
        emit ValueUpdate(newValue, dataFeedId, currentTimestamp);
    }
}