// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "./TestContracts/QuillDeployment.t.sol";

contract SentinelScrollTest is Test {
    ISequencerSentinel sequencerSentinel;
    address sequecencerOracle = 0x45c2b8C204568A03Dc7A2E32B71D67Fe97F908A9;

    function setUp() public {
        // Why doesn't this test use the QuillDeployment.t.sol contract?
        // 1. Scroll token didn't exist at the time of the only scroll-mainnet incident
        //    caught by the oracle sequecer. Some changes concerning number of collaterals are needed.
        // 2. rollFork loses the state of the previous fork, so we can't use the same contract for
        //    multiple tests without vm.makePersistent. QuillDeployment is not prepared for that
        vm.createSelectFork(vm.rpcUrl("scroll"));
        vm.label(sequecencerOracle, "sequecencerOracle");
    }

    function _loadSequencerDownFork() private {
        vm.rollFork(9_025_428); // first block where sequencer is down during 5th september 2024 outage
        sequencerSentinel = new QuillSequencerSentinel(address(this), sequecencerOracle, 3600);
    }

    function _loadUnderGracePeriod() private {
        vm.rollFork(9_025_878); // first block where sequencer is up during 5th september 2024 outage, startAt ~18h01
        sequencerSentinel = new QuillSequencerSentinel(address(this), sequecencerOracle, 3600);
    }

    function _loadOverGracePeriod() private {
        vm.rollFork(9_027_880); // first block where sequencer is up during 5th september 2024 outage, startAt ~18h01
        sequencerSentinel = new QuillSequencerSentinel(address(this), sequecencerOracle, 3600);
    }

    function testSequencerDownState() public {
        _loadSequencerDownFork();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        sequencerSentinel.requireUp();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        sequencerSentinel.requireUpAndOverGracePeriod();
    }

    function testSequencerUnderGracePeriod() public {
        _loadUnderGracePeriod();
        sequencerSentinel.requireUp();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        sequencerSentinel.requireUpAndOverGracePeriod();
    }

    function testSequencerOverGracePeriod() public {
        _loadOverGracePeriod();
        sequencerSentinel.requireUp();
        sequencerSentinel.requireUpAndOverGracePeriod();
    }
}
