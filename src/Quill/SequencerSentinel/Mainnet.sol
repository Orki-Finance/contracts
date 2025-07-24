// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "../../Dependencies/AggregatorV3Interface.sol";
import {ISequencerSentinel} from "../Interfaces/ISequencerSentinel.sol";

// mainnet version of QuillSequencerSentinel, innocuous by default
contract QuillSequencerSentinelMainnet is ISequencerSentinel {
    uint256 public gracePeriod;

    /// @inheritdoc ISequencerSentinel
    function requireUp() public view {}

    /// @inheritdoc ISequencerSentinel
    function requireUpAndOverGracePeriod() public view {}

    /// @inheritdoc ISequencerSentinel
    function setSequencerOracle(address newSequencerOracle) public {}

    /// @inheritdoc ISequencerSentinel
    function setGracePeriod(uint256 newGracePeriod) public {}
}
