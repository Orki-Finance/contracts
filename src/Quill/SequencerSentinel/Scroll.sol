// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "../../Dependencies/AggregatorV3Interface.sol";
import {ISequencerSentinel} from "../Interfaces/ISequencerSentinel.sol";
import {AccessManaged} from "openzeppelin-contracts/contracts/access/manager/AccessManaged.sol";

// based on aave-v3-core/contracts/protocol/configuration/PriceOracleSentinel.sol
contract QuillSequencerSentinel is ISequencerSentinel, AccessManaged {
    AggregatorV3Interface private sequencerFeed;

    uint256 public gracePeriod;

    /**
     * @dev Constructor
     * @param _sequencerFeed The address of the sequencer feed oracle
     * @param _gracePeriod The duration of the grace period in seconds
     */
    constructor(address _authority, address _sequencerFeed, uint256 _gracePeriod) AccessManaged(_authority) {
        sequencerFeed = AggregatorV3Interface(_sequencerFeed);
        gracePeriod = _gracePeriod;

        emit SequencerOracleUpdated(_sequencerFeed);
        emit GracePeriodUpdated(_gracePeriod);
    }

    /// @inheritdoc ISequencerSentinel
    function requireUp() public view {
        (, int256 answer,,,) = sequencerFeed.latestRoundData();
        if (answer != 0) {
            revert SequencerDown();
        }
    }

    /// @inheritdoc ISequencerSentinel
    function requireUpAndOverGracePeriod() public view {
        (, int256 answer, uint256 startAt,,) = sequencerFeed.latestRoundData();
        if (answer != 0) {
            revert SequencerDown();
        }
        if (block.timestamp - startAt < gracePeriod) {
            revert SystemUnderGracePeriod();
        }
    }

    /// @inheritdoc ISequencerSentinel
    function setSequencerOracle(address newSequencerOracle) public restricted {
        sequencerFeed = AggregatorV3Interface(newSequencerOracle);
        emit SequencerOracleUpdated(newSequencerOracle);
    }

    /// @inheritdoc ISequencerSentinel
    function setGracePeriod(uint256 newGracePeriod) public restricted {
        gracePeriod = newGracePeriod;
        emit GracePeriodUpdated(newGracePeriod);
    }
}
