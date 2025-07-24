// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "../TestContracts/DevTestSetup.sol";
import {DeployQuillBase} from "script/DeployQuillBase.sol";
import {setupAccessControl} from "script/SetupAccessControl.s.sol";
import {CollateralRegistryV2} from "./TestContracts/CollateralRegistryV2.sol";

contract UpgradesTest is DevTestSetup {
    address newAdmin = address(0x10);
    address emergencyReponder = address(0x11);
    address highPriorityAccount = address(0x12);
    address mediumPriorityAccount = address(0x13);
    address lowPriorityAccount = address(0x14);

    DeployQuillBase.DeploymentResult deployed;

    function setUp() public override {
        super.setUp();

        // There's no need for all contracts
        deployed.quillAccessManager = quillAccessManager;
        deployed.collateralRegistry = collateralRegistry;
        deployed.sequencerSentinel = sequencerSentinel;
        deployed.boldToken = boldToken;
        deployed.hintHelpers = hintHelpers;
        // deployed.multiTroveGetter=multiTroveGetter;

        (bool isAdmin,) = quillAccessManager.hasRole(quillAccessManager.ADMIN_ROLE(), addrDeployer);
        assertTrue(isAdmin);

        vm.startPrank(addrDeployer);
        address[] memory newAdmins = new address[](1);
        newAdmins[0] = newAdmin;

        address[] memory emergencyReponders = new address[](1);
        emergencyReponders[0] = emergencyReponder;

        address[] memory accountsForHighTimelock = new address[](1);
        accountsForHighTimelock[0] = highPriorityAccount;

        address[] memory accountsForMediumTimelock = new address[](1);
        accountsForMediumTimelock[0] = mediumPriorityAccount;

        address[] memory accountsForLowTimelock = new address[](1);
        accountsForLowTimelock[0] = lowPriorityAccount;

        setupAccessControl(
            addrDeployer,
            deployed,
            newAdmins,
            emergencyReponders,
            accountsForHighTimelock,
            accountsForMediumTimelock,
            accountsForLowTimelock
        );
        vm.stopPrank();

        (isAdmin,) = quillAccessManager.hasRole(quillAccessManager.ADMIN_ROLE(), addrDeployer);
        assertFalse(isAdmin);
    }

    function test_rolesGranted() public view {
        (bool emergencyReponderRole,) =
            quillAccessManager.hasRole(quillAccessManager.EMERGENCY_RESPONDER_ROLE(), emergencyReponder);
        assertTrue(emergencyReponderRole);

        (bool highPriorityAccountRole,) =
            quillAccessManager.hasRole(quillAccessManager.HIGH_PRIORITY_OPS_ROLE(), highPriorityAccount);
        assertTrue(highPriorityAccountRole);

        (bool mediumPriorityAccountRole,) =
            quillAccessManager.hasRole(quillAccessManager.MEDIUM_PRIORITY_OPS_ROLE(), mediumPriorityAccount);
        assertTrue(mediumPriorityAccountRole);

        (bool lowPriorityAccountRole,) =
            quillAccessManager.hasRole(quillAccessManager.LOW_PRIORITY_OPS_ROLE(), lowPriorityAccount);
        assertTrue(lowPriorityAccountRole);

        (bool isAdmin,) = quillAccessManager.hasRole(quillAccessManager.ADMIN_ROLE(), newAdmin);
        assertTrue(isAdmin);
    }

    function test_adminDelays_grantAdminRole() public {
        (bool isAdmin,) = quillAccessManager.hasRole(quillAccessManager.ADMIN_ROLE(), addrDeployer);
        assertFalse(isAdmin);

        vm.startPrank(newAdmin);
        quillAccessManager.schedule(
            address(quillAccessManager),
            abi.encodeWithSelector(
                quillAccessManager.grantRole.selector, quillAccessManager.ADMIN_ROLE(), addrDeployer, 0
            ),
            0
        );

        skip(quillAccessManager.ADMIN_ROLE_TIMELOCK());

        quillAccessManager.execute(
            address(quillAccessManager),
            abi.encodeWithSelector(
                quillAccessManager.grantRole.selector, quillAccessManager.ADMIN_ROLE(), addrDeployer, 0
            )
        );
        vm.stopPrank();

        (isAdmin,) = quillAccessManager.hasRole(quillAccessManager.ADMIN_ROLE(), addrDeployer);
        assertFalse(isAdmin);

        skip(quillAccessManager.ADMIN_ROLE_GRANT_TIMELOCK());

        (isAdmin,) = quillAccessManager.hasRole(quillAccessManager.ADMIN_ROLE(), addrDeployer);
        assertTrue(isAdmin);
    }

    function test_setCRValues() public {
        uint256 troveIndex = 0;
        uint256 newCCR = 151e16;
        uint256 newMCR = 111e16;
        uint256 newSCR = 111e16;

        // CCR
        vm.startPrank(mediumPriorityAccount);
        quillAccessManager.schedule(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveCCR.selector, troveIndex, newCCR),
            0
        );

        vm.expectPartialRevert(IAccessManager.AccessManagerNotReady.selector);
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveCCR.selector, troveIndex, newCCR)
        );

        skip(quillAccessManager.MEDIUM_PRIORITY_TIMELOCK());
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveCCR.selector, troveIndex, newCCR)
        );
        vm.stopPrank();

        // MCR
        vm.startPrank(mediumPriorityAccount);
        quillAccessManager.schedule(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveMCR.selector, troveIndex, newMCR),
            0
        );

        vm.expectPartialRevert(IAccessManager.AccessManagerNotReady.selector);
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveMCR.selector, troveIndex, newMCR)
        );

        skip(quillAccessManager.MEDIUM_PRIORITY_TIMELOCK());
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveMCR.selector, troveIndex, newMCR)
        );
        vm.stopPrank();

        // SCR
        vm.startPrank(mediumPriorityAccount);
        quillAccessManager.schedule(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveSCR.selector, troveIndex, newSCR),
            0
        );

        vm.expectPartialRevert(IAccessManager.AccessManagerNotReady.selector);
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveSCR.selector, troveIndex, newSCR)
        );

        skip(quillAccessManager.MEDIUM_PRIORITY_TIMELOCK());
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setTroveSCR.selector, troveIndex, newSCR)
        );
        vm.stopPrank();

        assertEq(collateralRegistry.getTroveManager(troveIndex).CCR(), newCCR);
        assertEq(collateralRegistry.getTroveManager(troveIndex).MCR(), newMCR);
        assertEq(collateralRegistry.getTroveManager(troveIndex).SCR(), newSCR);
    }

    function test_setSPYieldSplit() public {
        uint256 troveIndex = 0;
        uint256 newValue = _100pct / 5;

        vm.startPrank(lowPriorityAccount);
        quillAccessManager.schedule(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setSPYieldSplit.selector, troveIndex, newValue),
            0
        );

        vm.expectPartialRevert(IAccessManager.AccessManagerNotReady.selector);
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setSPYieldSplit.selector, troveIndex, newValue)
        );

        skip(quillAccessManager.LOW_PRIORITY_TIMELOCK());
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setSPYieldSplit.selector, troveIndex, newValue)
        );
        vm.stopPrank();

        assertEq(activePool.stabilityPoolYieldSplit(), newValue);
    }

    function test_setInterestRouter() public {
        uint256 troveIndex = 0;
        address newValue = address(0x123456789);

        vm.startPrank(lowPriorityAccount);
        quillAccessManager.schedule(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setInterestRouter.selector, troveIndex, newValue),
            0
        );

        vm.expectPartialRevert(IAccessManager.AccessManagerNotReady.selector);
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setInterestRouter.selector, troveIndex, newValue)
        );

        skip(quillAccessManager.LOW_PRIORITY_TIMELOCK());
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(collateralRegistry.setInterestRouter.selector, troveIndex, newValue)
        );
        vm.stopPrank();

        assertEq(address(activePool.interestRouter()), newValue);
    }

    function test_shutdownBranch() public {
        uint256 troveIndex = 0;

        vm.startPrank(lowPriorityAccount);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        collateralRegistry.shutdownBranch(troveIndex);
        vm.stopPrank();

        vm.startPrank(mediumPriorityAccount);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        collateralRegistry.shutdownBranch(troveIndex);
        vm.stopPrank();

        vm.startPrank(highPriorityAccount);
        vm.expectPartialRevert(IAccessManaged.AccessManagedUnauthorized.selector);
        collateralRegistry.shutdownBranch(troveIndex);
        vm.stopPrank();

        vm.startPrank(emergencyReponder);
        collateralRegistry.shutdownBranch(troveIndex);
        vm.stopPrank();
    }

    function test_upgradeableContract() public {
        CollateralRegistryV2 collateralRegistryV2 = new CollateralRegistryV2();

        vm.startPrank(highPriorityAccount);
        quillAccessManager.schedule(
            address(collateralRegistry),
            abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(collateralRegistryV2),
                abi.encodeCall(CollateralRegistryV2.initializeV2, ())
            ),
            0
        );

        vm.expectPartialRevert(IAccessManager.AccessManagerNotReady.selector);
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(collateralRegistryV2),
                abi.encodeCall(CollateralRegistryV2.initializeV2, ())
            )
        );

        skip(quillAccessManager.HIGH_PRIORITY_TIMELOCK());
        quillAccessManager.execute(
            address(collateralRegistry),
            abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(collateralRegistryV2),
                abi.encodeCall(CollateralRegistryV2.initializeV2, ())
            )
        );
        vm.stopPrank();

        assertEq(CollateralRegistryV2(address(collateralRegistry)).newVariable(), 42);
    }
}
