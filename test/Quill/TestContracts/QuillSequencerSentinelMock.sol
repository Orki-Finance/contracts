// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "src/Quill/Interfaces/ISequencerSentinel.sol";

import "forge-std/console.sol";

contract SequencerSentinelMock is ISequencerSentinel {
    uint256 public gracePeriod;
    uint256 private startAt;
    uint256 private answer;

    function requireUpAndOverGracePeriod() external view {
        if (answer != 0) {
            revert SequencerDown();
        }
        if (block.timestamp - startAt < gracePeriod) {
            revert SystemUnderGracePeriod();
        }
    }

    function requireUp() external view {
        if (answer != 0) {
            revert SequencerDown();
        }
    }

    function setGracePeriod(uint256 newGracePeriod) external {
        gracePeriod = newGracePeriod;
    }

    function setSequencerOracle(address newSequencerOracle) external {
        // do nothing
    }

    // helper for setting tests
    function setAnswer(uint256 _answer) public {
        answer = _answer;
    }

    function setStartAt(uint256 _startAt) public {
        startAt = _startAt;
    }
}
