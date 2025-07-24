// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./TestContracts/QuillTestSetup.sol";
import {SequencerSentinelMock} from "./TestContracts/QuillSequencerSentinelMock.sol";

contract QuillSentinelTest is QuillTestSetup {
    SequencerSentinelMock sentinelMock;

    function setUp() public override {
        super.setUp();
        vm.etch(address(sequencerSentinel), type(SequencerSentinelMock).runtimeCode);
        sentinelMock = SequencerSentinelMock(address(sequencerSentinel));
        skip(3600);
        sentinelMock.setGracePeriod(3600);
    }

    function _generateTrove(uint256 price, uint256 troveDebtRequest, uint256 interestRate)
        private
        returns (uint256 ATroveId)
    {
        priceFeed.setPrice(price);
        ATroveId = openTroveNoHints100pct(A, 3 ether, troveDebtRequest, interestRate);
    }

    function _setInvalidStateSequencerDown() public {
        console.log(address(sentinelMock));
        sentinelMock.setAnswer(1);
        skip(3600);
        sentinelMock.setStartAt(block.timestamp);
    }

    function _setValidStateUnderGracePeriod() public {
        sentinelMock.setAnswer(0); //sequecencer is up, we want it valid but under grace period
        sentinelMock.setStartAt(block.timestamp + 1800);
        skip(3600);
    }

    // CR#redeemCollateral
    // [ ] down -> [ ] under grace period -> [x] up
    function testRedemptionUnderDifferentStates() public {
        (,, ABCDEF memory troveIDs) = _setupForRedemptionAscendingInterest();

        uint256 debt_A = troveManager.getTroveEntireDebt(troveIDs.A);
        uint256 debt_B = troveManager.getTroveEntireDebt(troveIDs.B);
        uint256 redeemAmount_1 = debt_A + debt_B / 2;
        uint256 snapshot = vm.snapshotState();

        // jumps a day and confirms ability to redeem
        vm.warp(block.timestamp + 3600);
        redeem(E, redeemAmount_1);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        redeem(E, redeemAmount_1);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        redeem(E, redeemAmount_1);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#withdrawColl
    // [ ] down -> [ ] under grace period -> [x] up
    function testWithdrawCollUnderDifferentStates() public {
        uint256 collIncrease = 1 ether;
        uint256 ATroveId = _generateTrove(2000e18, 2000e18, 25e16);
        uint256 snapshot = vm.snapshotState();

        // jumps a day and confirms ability to redeem
        vm.warp(block.timestamp + 3600);
        withdrawColl(A, ATroveId, collIncrease);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        withdrawColl(A, ATroveId, collIncrease);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        withdrawColl(A, ATroveId, collIncrease);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#addColl
    // [ ] down -> [x] under grace period -> [ ] up
    function testAddCollUnderDifferentStates() public {
        uint256 collIncrease = 1 ether;
        uint256 ATroveId = _generateTrove(2000e18, 2000e18, 25e16);
        uint256 snapshot = vm.snapshotState();

        // jumps a day and confirms ability to redeem
        vm.warp(block.timestamp + 3600);
        addColl(A, ATroveId, collIncrease);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        addColl(A, ATroveId, collIncrease);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        // Don't expect a revert here, as addColl improves trove's and branch's health
        addColl(A, ATroveId, collIncrease);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#repayBold
    // [ ] down -> [x] under grace period -> [ ] up
    function testRepayBoldUnderDifferentStates() public {
        uint256 boldRepayment = 500e18;
        uint256 ATroveId = _generateTrove(3000e18, 2000e18, 25e16);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        repayBold(A, ATroveId, boldRepayment);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        repayBold(A, ATroveId, boldRepayment);

        vm.revertToState(snapshot);
        // Don't expect a revert here, as addColl improves trove's and branch's health
        repayBold(A, ATroveId, boldRepayment);

        vm.deleteStateSnapshot(snapshot);
    }

    // Can't reuse withdrawBold100pct
    function _withdrawBold100pct(address _account, uint256 _troveId, uint256 _debtIncrease, uint256 pred) private {
        vm.startPrank(_account);
        borrowerOperations.withdrawBold(_troveId, _debtIncrease, pred);
        vm.stopPrank();
    }

    // BO#withdrawBold
    // [ ] down -> [ ] under grace period -> [x] up
    function testWithdrawBoldUnderDifferentStates() public {
        uint256 boldWithdrawal = 500e18;
        uint256 ATroveId = _generateTrove(2000e18, 2000e18, 25e16);
        uint256 pred = predictAdjustTroveUpfrontFee(ATroveId, boldWithdrawal);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        _withdrawBold100pct(A, ATroveId, boldWithdrawal, pred);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        _withdrawBold100pct(A, ATroveId, boldWithdrawal, pred);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        _withdrawBold100pct(A, ATroveId, boldWithdrawal, pred);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#closeTrove
    // [ ] down -> [ ] under grace period -> [x] up
    function testCloseTroveUnderDifferentStates() public {
        priceFeed.setPrice(2000e18);
        vm.startPrank(A);
        borrowerOperations.openTrove(
            A, 0, 2e18, 2000e18, 0, 0, troveManager.minAnnualInterestRate(), 1000e18, address(0), address(0), address(0)
        );
        // Transfer some Bold to B so that B can close Trove accounting for interest and upfront fee
        boldToken.transfer(B, 100e18);
        vm.stopPrank();

        vm.startPrank(B);
        uint256 B_Id = borrowerOperations.openTrove(
            B, 0, 2e18, 2000e18, 0, 0, troveManager.minAnnualInterestRate(), 1000e18, address(0), address(0), address(0)
        );
        vm.stopPrank();
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        closeTrove(B, B_Id);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        closeTrove(B, B_Id);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        closeTrove(B, B_Id);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#shutdown
    // [ ] down -> [ ] under grace period -> [x] up
    function testShutdownUnderDifferentStates() public {
        priceFeed.setPrice(2000e18);
        vm.startPrank(A);
        borrowerOperations.openTrove(
            A, 0, 2e18, 2000e18, 0, 0, troveManager.minAnnualInterestRate(), 1000e18, address(0), address(0), address(0)
        );
        vm.stopPrank();
        priceFeed.setPrice(1000e18);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        borrowerOperations.shutdown();

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        borrowerOperations.shutdown();

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        borrowerOperations.shutdown();

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#setBatchManagerAnnualInterestRate
    // [ ] down -> [ ] under grace period -> [x] up
    function testSetBatchManagerAnnualInterestRateUnderDifferentStates() public {
        openTroveAndJoinBatchManager();
        // Fast forward 1 year as in the original test interesentBatchManagement.t.sol#testChangeBatchInterestRate
        vm.warp(block.timestamp + 365 days);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.startPrank(B);
        borrowerOperations.setBatchManagerAnnualInterestRate(6e16, 0, 0, 100000e18);
        vm.stopPrank();

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.startPrank(B);
        borrowerOperations.setBatchManagerAnnualInterestRate(6e16, 0, 0, 100000e18);
        vm.stopPrank();

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.startPrank(B);
        borrowerOperations.setBatchManagerAnnualInterestRate(6e16, 0, 0, 100000e18);
        vm.stopPrank();

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#adjustTroveInterestRate
    // [ ] down -> [x] under grace period -> [x] up
    function testAdjustTroveInterestRateUnderDifferentStates() public {
        uint256 troveId = openTroveNoHints100pct(A, 100 ether, 10_000 ether, 0.05 ether);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.adjustTroveInterestRate(troveId, 0.06 ether, 0, 0, 1000e18);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.adjustTroveInterestRate(troveId, 0.06 ether, 0, 0, 1000e18);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        borrowerOperations.adjustTroveInterestRate(troveId, 0.06 ether, 0, 0, 1000e18);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#setInterestBatchManager
    // [ ] down -> [x] under grace period -> [ ] up
    function testSetInterestBatchManagerUnderDifferentStates() public {
        registerBatchManager(B);
        uint256 troveId = openTroveNoHints100pct(A, 100e18, 5000e18, 5e16);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.setInterestBatchManager(troveId, B, 0, 0, 1e24);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.setInterestBatchManager(troveId, B, 0, 0, 1e24);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        borrowerOperations.setInterestBatchManager(troveId, B, 0, 0, 1e24);

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#removeFromBatch
    // [ ] down -> [ ] under grace period -> [x] up
    function testRemoveFromBatchUnderDifferentStates() public {
        uint256 troveId = openTroveAndJoinBatchManager();
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.removeFromBatch(troveId, 5e16, 0, 0, 1000e18);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.removeFromBatch(troveId, 5e16, 0, 0, 1000e18);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        borrowerOperations.removeFromBatch(troveId, 5e16, 0, 0, 1000e18);

        vm.deleteStateSnapshot(snapshot);
    }

    // TM#batchLiquidateTroves
    // [ ] down -> [ ] under grace period -> [x] up
    // There's probably better targets, but tried to find that had few dependencies
    function testBatchLiquidateTrovesUnderDifferentStates() public {
        ABCDEF memory troveIDs;

        uint256 coll = 100 ether;
        uint256 borrow = 10_000 ether;
        uint256 interestRate = 0.01 ether;
        troveIDs.A = openTroveNoHints100pct(A, coll, borrow, interestRate);
        troveIDs.B = openTroveNoHints100pct(B, coll, borrow, interestRate);
        troveIDs.C = openTroveNoHints100pct(C, coll, borrow, interestRate);
        troveIDs.D = openTroveNoHints100pct(D, 1_000 ether, borrow, interestRate); // whale to keep TCR afloat

        uint256 dropPrice = 110 ether;
        priceFeed.setPrice(dropPrice);
        assertGt(troveManager.getTCR(dropPrice), CCR, "Want TCR > CCR");
        uint256[] memory liquidatedTroves = new uint256[](2);
        liquidatedTroves[0] = troveIDs.A; // inactive
        liquidatedTroves[1] = troveIDs.B;
        uint256 snapshot = vm.snapshotState();

        // core test
        vm.warp(block.timestamp + 3600);
        troveManager.batchLiquidateTroves(liquidatedTroves);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        troveManager.batchLiquidateTroves(liquidatedTroves);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        troveManager.batchLiquidateTroves(liquidatedTroves);

        vm.deleteStateSnapshot(snapshot);
    }

    // TM#urgentRedeem
    // [ ] down -> [ ] under grace period -> [x] up
    function testUrgentRedeemUnderDifferentStates() public {
        priceFeed.setPrice(2000e18);
        vm.startPrank(A);
        uint256 troveId = borrowerOperations.openTrove(
            A, 0, 2e18, 2000e18, 0, 0, troveManager.minAnnualInterestRate(), 1000e18, address(0), address(0), address(0)
        );
        vm.stopPrank();
        priceFeed.setPrice(1000e18);
        borrowerOperations.shutdown();
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        troveManager.urgentRedemption(1000e18, uintToArray(troveId), 101e16);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        troveManager.urgentRedemption(1000e18, uintToArray(troveId), 101e16);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        troveManager.urgentRedemption(1000e18, uintToArray(troveId), 101e16);

        vm.deleteStateSnapshot(snapshot);
    }

    // TM#getUnbackedPortionPriceAndRedeemability
    // [ ] down -> [ ] under grace period -> [x] up
    function testUnbackedPortionPriceAndRedeemabilityUnderDifferentStates() public {
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        troveManager.getUnbackedPortionPriceAndRedeemability();

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        troveManager.getUnbackedPortionPriceAndRedeemability();

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        troveManager.getUnbackedPortionPriceAndRedeemability();

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#openTrove
    // [ ] down -> [ ] under grace period -> [x] up
    function testOpenTroveUnderDifferentStates() public {
        priceFeed.setPrice(3000e18);
        uint256 snapshot = vm.snapshotState();
        uint256 minInterestRate = troveManager.minAnnualInterestRate();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.openTrove(
            A, 0, 2e18, 2000e18, 0, 0, minInterestRate, 1000e18, address(0), address(0), address(0)
        );

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.openTrove(
            A, 0, 2e18, 2000e18, 0, 0, minInterestRate, 1000e18, address(0), address(0), address(0)
        );

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        borrowerOperations.openTrove(
            A, 0, 2e18, 2000e18, 0, 0, minInterestRate, 1000e18, address(0), address(0), address(0)
        );

        vm.deleteStateSnapshot(snapshot);
    }

    // BO#openTroveAndJoinInterestBatchManager
    // [ ] down -> [ ] under grace period -> [x] up
    function testOpenTroveAndJoinInterestBatchManagerUnderDifferentStates() public {
        ABCDEF memory troveIDs;

        troveIDs.A = openTroveAndJoinBatchManager();

        // Register a new batch manager and add a trove to it
        registerBatchManager(C);
        IBorrowerOperations.OpenTroveAndJoinInterestBatchManagerParams memory paramsD = IBorrowerOperations
            .OpenTroveAndJoinInterestBatchManagerParams({
            owner: D,
            ownerIndex: 0,
            collAmount: 100e18,
            boldAmount: 5000e18,
            upperHint: 0,
            lowerHint: 0,
            interestBatchManager: C,
            maxUpfrontFee: 1e24,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(D);
        troveIDs.D = borrowerOperations.openTroveAndJoinInterestBatchManager(paramsD);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(D);
        troveIDs.D = borrowerOperations.openTroveAndJoinInterestBatchManager(paramsD);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(D);
        troveIDs.D = borrowerOperations.openTroveAndJoinInterestBatchManager(paramsD);

        vm.deleteStateSnapshot(snapshot);
    }

    // T ODO: Change this test to be a fuzz test (low priority)
    //BO#adjustTrove
    // if newICR > oldICR : [ ] down -> [x] under grace period -> [ ] up
    // if oldICR > newICR : [ ] down -> [ ] under grace period -> [x] up
    function testAdjustTroveUnderDifferentStates() public {
        priceFeed.setPrice(2000e18);
        uint256 troveId = openTroveNoHints100pct(A, 100 ether, 10_000 ether, 0.05 ether); // ICR = 200%

        // First case: newICR > oldICR by increasing collateral
        uint256 collChange = 1 ether;
        bool isCollIncrease = true;
        uint256 boldChange = 0;
        bool isDebtIncrease = false;
        uint256 pred = predictAdjustTroveUpfrontFee(troveId, isDebtIncrease ? boldChange : 0);

        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        // all good
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        vm.deleteStateSnapshot(snapshot);

        // Second case: newICR > oldICR by decreasing debt
        collChange = 0;
        isCollIncrease = false;
        boldChange = 1 ether;
        isDebtIncrease = false;
        pred = predictAdjustTroveUpfrontFee(troveId, isDebtIncrease ? boldChange : 0);
        snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        // all good
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        vm.deleteStateSnapshot(snapshot);

        // third case: oldICR > newICR by decreasing colateral
        collChange = 1 ether;
        isCollIncrease = false;
        boldChange = 0;
        isDebtIncrease = false;
        pred = predictAdjustTroveUpfrontFee(troveId, isDebtIncrease ? boldChange : 0);
        snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        vm.deleteStateSnapshot(snapshot);

        // fourth case: oldICR > newICR by increasing debt
        collChange = 0;
        isCollIncrease = false;
        boldChange = 1 ether;
        isDebtIncrease = true;
        pred = predictAdjustTroveUpfrontFee(troveId, isDebtIncrease ? boldChange : 0);
        snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(A);
        borrowerOperations.adjustTrove(troveId, collChange, isCollIncrease, boldChange, isDebtIncrease, pred);

        vm.revertToState(snapshot);
        vm.deleteStateSnapshot(snapshot);
    }

    // T ODO: Change this test to be a fuzz test (low priority)
    //BO#adjustZombieTrove
    // if newICR > oldICR : [ ] down -> [x] under grace period -> [ ] up
    // if oldICR > newICR : [ ] down -> [ ] under grace period -> [x] up
    // Testing adjustZombieTrove must take MIN_DEBT into account
    function testAdjustZombieTroveUnderDifferentStates() public {
        (,, ABCDEF memory troveIDs) = _setupForRedemptionAscendingInterest();

        _redeemAndCreateZombieTrovesAAndB(troveIDs);

        uint256 collChange = 0;
        bool isCollIncrease = false;
        uint256 boldChange = troveManager.MIN_DEBT();
        bool isDebtIncrease = true;
        uint256 pred = predictAdjustTroveUpfrontFee(troveIDs.B, isDebtIncrease ? boldChange : 0);
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 3600);
        vm.prank(B);
        borrowerOperations.adjustZombieTrove(
            troveIDs.B, collChange, isCollIncrease, boldChange, isDebtIncrease, 0, 0, pred
        );

        vm.revertToState(snapshot);
        _setInvalidStateSequencerDown();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SequencerDown.selector));
        vm.prank(B);
        borrowerOperations.adjustZombieTrove(
            troveIDs.B, collChange, isCollIncrease, boldChange, isDebtIncrease, 0, 0, pred
        );

        vm.revertToState(snapshot);
        _setValidStateUnderGracePeriod();
        vm.expectRevert(abi.encodeWithSelector(ISequencerSentinel.SystemUnderGracePeriod.selector));
        vm.prank(B);
        borrowerOperations.adjustZombieTrove(
            troveIDs.B, collChange, isCollIncrease, boldChange, isDebtIncrease, 0, 0, pred
        );

        vm.revertToState(snapshot);
        vm.deleteStateSnapshot(snapshot);
    }
}
