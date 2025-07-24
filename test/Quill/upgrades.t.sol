// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../TestContracts/DevTestSetup.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CollateralRegistryV2} from "./TestContracts/CollateralRegistryV2.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
// import {ICollateralRegistry} from "../Interfaces/ICollateralRegistry.sol";

// Redo the basicOps tests after an Upgrade
contract UpgradesTest is DevTestSetup {
    function setUp() public override {
        super.setUp();
    }

    function _applyUpgrade() internal {
        // Deploy the new implementation contract
        CollateralRegistryV2 collateralRegistryV2 = new CollateralRegistryV2(); // implementation

        vm.startPrank(addrDeployer);
        UnsafeUpgrades.upgradeProxy(
            address(collateralRegistry),
            address(collateralRegistryV2),
            abi.encodeCall(CollateralRegistryV2.initializeV2, ())
        );
        vm.stopPrank();

        // Check that the upgrade was successful
        assertEq(CollateralRegistryV2(address(collateralRegistry)).newVariable(), 42);
    }

    function _diffTestRedeem(uint256 B_Id, uint256 debt_1, uint256 coll_1) private {
        uint256 redemptionAmount = 1000e18; // 1k BOLD

        // A redeems 1k BOLD
        vm.startPrank(A);
        collateralRegistry.redeemCollateral(redemptionAmount, 10, 1e18);

        // Check B's coll and debt reduced
        uint256 debt_2 = troveManager.getTroveDebt(B_Id);
        assertLt(debt_2, debt_1);
        uint256 coll_2 = troveManager.getTroveColl(B_Id);
        assertLt(coll_2, coll_1);
    }

    function testRedeem() public {
        priceFeed.setPrice(2000e18);

        vm.startPrank(A);
        borrowerOperations.openTrove(
            A,
            0,
            5e18,
            5_000e18,
            0,
            0,
            troveManager.minAnnualInterestRate(),
            1000e18,
            address(0),
            address(0),
            address(0)
        );
        vm.stopPrank();

        vm.startPrank(B);
        uint256 B_Id = borrowerOperations.openTrove(
            B,
            0,
            5e18,
            4_000e18,
            0,
            0,
            troveManager.minAnnualInterestRate(),
            1000e18,
            address(0),
            address(0),
            address(0)
        );
        uint256 debt_1 = troveManager.getTroveDebt(B_Id);
        assertGt(debt_1, 0);
        uint256 coll_1 = troveManager.getTroveColl(B_Id);
        assertGt(coll_1, 0);
        vm.stopPrank();

        // Wait some time so that redemption rate is not 100%
        vm.warp(block.timestamp + 7 days);

        // B is now first in line to get redeemed, as they both have the same interest rate,
        // but B's Trove is younger.
        uint256 snapshot = vm.snapshotState();

        _diffTestRedeem(B_Id, debt_1, coll_1);

        vm.revertToStateAndDelete(snapshot);

        _applyUpgrade();

        _diffTestRedeem(B_Id, debt_1, coll_1);
    }
}
