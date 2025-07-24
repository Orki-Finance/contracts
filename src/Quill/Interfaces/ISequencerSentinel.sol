// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISequencerSentinel {
    /**
     * @dev Emitted after the grace period is updated
     * @param newGracePeriod The new grace period value
     */
    event GracePeriodUpdated(uint256 newGracePeriod);

    /**
     * @dev Emitted after the SequencerOracle is updated
     * @param newSequencerOracle The new SequencerOracle address
     */
    event SequencerOracleUpdated(address newSequencerOracle);

    error SequencerDown();
    error SystemUnderGracePeriod();

    /**
     * @notice Reverts if sequencer is down.
     * @dev Operation not allowed when Sequencer feed returns `answer == 1`.
     */
    function requireUp() external view;

    /**
     * @notice Reverts if system is down or if system is under grace period.
     * @dev Operation allowed when sequencer feed returns `answer == 0` and  `startAt` + gracePeriod < block.timestamp.
     */
    function requireUpAndOverGracePeriod() external view;

    /**
     * @notice Updates the oracle's address
     * @param newSequencerOracle The address of the new SequencerOracle
     */
    function setSequencerOracle(address newSequencerOracle) external;

    /**
     * @notice Updates the duration of the grace period
     * @param newGracePeriod The value of the new grace period duration
     */
    function setGracePeriod(uint256 newGracePeriod) external;

    /**
     * @notice Returns the grace period
     * @return The duration of the grace period
     */
    function gracePeriod() external view returns (uint256);
}
