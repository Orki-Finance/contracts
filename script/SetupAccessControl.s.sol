// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {DeployQuillBase} from "./DeployQuillBase.sol";
import {ICollateralRegistry} from "src/Interfaces/ICollateralRegistry.sol";
import {ISequencerSentinel} from "src/Quill/Interfaces/ISequencerSentinel.sol";
import {QuillAccessManagerUpgradeable} from "src/Quill/QuillAccessManagerUpgradeable.sol";

function setupAccessControl(
    address deployer,
    DeployQuillBase.DeploymentResult memory deployed,
    address[] memory newAdmins,
    address[] memory emergencyReponders,
    address[] memory accountsForHighTimelock,
    address[] memory accountsForMediumTimelock,
    address[] memory accountsForLowTimelock
) {
    assert(newAdmins.length > 0);
    assert(emergencyReponders.length > 0);
    assert(accountsForHighTimelock.length > 0);
    assert(accountsForMediumTimelock.length > 0);
    assert(accountsForLowTimelock.length > 0);

    uint256 i;

    // ADMIN_ROLE
    for (i = 0; i < newAdmins.length; i++) {
        deployed.quillAccessManager.grantRole(
            deployed.quillAccessManager.ADMIN_ROLE(),
            newAdmins[i],
            deployed.quillAccessManager.ADMIN_ROLE_TIMELOCK() // Execution delay
        );
    }

    deployed.quillAccessManager.setGrantDelay(
        deployed.quillAccessManager.ADMIN_ROLE(), deployed.quillAccessManager.ADMIN_ROLE_GRANT_TIMELOCK()
    );

    // EMERGENCY_RESPONDER_ROLE
    deployed.quillAccessManager.setGrantDelay(
        deployed.quillAccessManager.EMERGENCY_RESPONDER_ROLE(),
        0 // Update the delay for granting a `roleId`.
    );

    for (i = 0; i < emergencyReponders.length; i++) {
        deployed.quillAccessManager.grantRole(
            deployed.quillAccessManager.EMERGENCY_RESPONDER_ROLE(),
            emergencyReponders[i],
            0 // Execution delay
        );
    }

    // HIGH_PRIORITY_OPS_ROLE
    deployed.quillAccessManager.setGrantDelay(
        deployed.quillAccessManager.HIGH_PRIORITY_OPS_ROLE(),
        0 // Update the delay for granting a `roleId`.
    );

    for (i = 0; i < accountsForHighTimelock.length; i++) {
        deployed.quillAccessManager.grantRole(
            deployed.quillAccessManager.HIGH_PRIORITY_OPS_ROLE(),
            accountsForHighTimelock[i],
            deployed.quillAccessManager.HIGH_PRIORITY_TIMELOCK() // Execution delay
        );
    }

    // MEDIUM_PRIORITY_OPS_ROLE
    deployed.quillAccessManager.setGrantDelay(
        deployed.quillAccessManager.MEDIUM_PRIORITY_OPS_ROLE(),
        0 // Update the delay for granting a `roleId`.
    );

    for (i = 0; i < accountsForMediumTimelock.length; i++) {
        deployed.quillAccessManager.grantRole(
            deployed.quillAccessManager.MEDIUM_PRIORITY_OPS_ROLE(),
            accountsForMediumTimelock[i],
            deployed.quillAccessManager.MEDIUM_PRIORITY_TIMELOCK() // Execution delay
        );
    }

    // LOW_PRIORITY_OPS_ROLE
    deployed.quillAccessManager.setGrantDelay(
        deployed.quillAccessManager.LOW_PRIORITY_OPS_ROLE(),
        0 // Update the delay for granting a `roleId`.
    );

    for (i = 0; i < accountsForLowTimelock.length; i++) {
        deployed.quillAccessManager.grantRole(
            deployed.quillAccessManager.LOW_PRIORITY_OPS_ROLE(),
            accountsForLowTimelock[i],
            deployed.quillAccessManager.LOW_PRIORITY_TIMELOCK() // Execution delay
        );
    }

    setupAccessControlCollateralRegistry(deployed.quillAccessManager, address(deployed.collateralRegistry));
    setupAccessControlSequencerSentinel(deployed.quillAccessManager, address(deployed.sequencerSentinel));
    setupAccessControlUpgradeableContracts(deployed);

    // Revoke ADMIN role from deployer
    deployed.quillAccessManager.revokeRole(deployed.quillAccessManager.ADMIN_ROLE(), deployer);
}

function setupAccessControlCollateralRegistry(
    QuillAccessManagerUpgradeable quillAccessManager,
    address collateralRegistry
) {
    bytes4[] memory selectorsForERR = new bytes4[](1);
    selectorsForERR[0] = ICollateralRegistry.shutdownBranch.selector;

    bytes4[] memory selectorsForHighTimelock = new bytes4[](1);
    selectorsForHighTimelock[0] = ICollateralRegistry.setTokenCap.selector;

    bytes4[] memory selectorsForMediumTimelock = new bytes4[](4);
    selectorsForMediumTimelock[0] = ICollateralRegistry.addCollateral.selector;
    selectorsForMediumTimelock[1] = ICollateralRegistry.setTroveCCR.selector;
    selectorsForMediumTimelock[2] = ICollateralRegistry.setTroveMCR.selector;
    selectorsForMediumTimelock[3] = ICollateralRegistry.setTroveSCR.selector;

    bytes4[] memory selectorsForLowTimelock = new bytes4[](3);
    selectorsForLowTimelock[0] = ICollateralRegistry.decreaseMinAnnualInterestRate.selector;
    selectorsForLowTimelock[1] = ICollateralRegistry.setSPYieldSplit.selector;
    selectorsForLowTimelock[2] = ICollateralRegistry.setInterestRouter.selector;

    quillAccessManager.setTargetFunctionRole(
        collateralRegistry, selectorsForERR, quillAccessManager.EMERGENCY_RESPONDER_ROLE()
    );

    quillAccessManager.setTargetFunctionRole(
        collateralRegistry, selectorsForHighTimelock, quillAccessManager.HIGH_PRIORITY_OPS_ROLE()
    );

    quillAccessManager.setTargetFunctionRole(
        collateralRegistry, selectorsForMediumTimelock, quillAccessManager.MEDIUM_PRIORITY_OPS_ROLE()
    );

    quillAccessManager.setTargetFunctionRole(
        collateralRegistry, selectorsForLowTimelock, quillAccessManager.LOW_PRIORITY_OPS_ROLE()
    );
}

function setupAccessControlSequencerSentinel(
    QuillAccessManagerUpgradeable quillAccessManager,
    address sequencerSentinel
) {
    bytes4[] memory selectorsForHighTimelock = new bytes4[](2);
    selectorsForHighTimelock[0] = ISequencerSentinel.setGracePeriod.selector;
    selectorsForHighTimelock[1] = ISequencerSentinel.setSequencerOracle.selector;

    quillAccessManager.setTargetFunctionRole(
        sequencerSentinel, selectorsForHighTimelock, quillAccessManager.HIGH_PRIORITY_OPS_ROLE()
    );
}

function setupAccessControlUpgradeableContracts(DeployQuillBase.DeploymentResult memory deployed) {
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;

    // BoldToken
    deployed.quillAccessManager.setTargetFunctionRole(
        address(deployed.boldToken), selectors, deployed.quillAccessManager.HIGH_PRIORITY_OPS_ROLE()
    );

    // CollateralRegistry
    deployed.quillAccessManager.setTargetFunctionRole(
        address(deployed.collateralRegistry), selectors, deployed.quillAccessManager.HIGH_PRIORITY_OPS_ROLE()
    );

    // HintHelpers
    deployed.quillAccessManager.setTargetFunctionRole(
        address(deployed.hintHelpers), selectors, deployed.quillAccessManager.HIGH_PRIORITY_OPS_ROLE()
    );

    // MultiTroveGetter
    deployed.quillAccessManager.setTargetFunctionRole(
        address(deployed.multiTroveGetter), selectors, deployed.quillAccessManager.HIGH_PRIORITY_OPS_ROLE()
    );
}
