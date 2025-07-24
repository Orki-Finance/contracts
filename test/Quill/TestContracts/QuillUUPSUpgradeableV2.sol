// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/manager/AccessManagedUpgradeable.sol";

abstract contract QuillUUPSUpgradeableV2 is Initializable, UUPSUpgradeable, AccessManagedUpgradeable {
    uint256 public newVariable;

    event NewQuillVariableUpdated(uint256 newValue);

    function __QuillUUPSUpgradeableV2_init() internal onlyInitializing {
        // Initialize new variables in V2
        newVariable = 42;
    }

    function setNewVariable(uint256 _newValue) external restricted {
        newVariable = _newValue;
        emit NewQuillVariableUpdated(_newValue);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    uint256[49] private __gap; // Reduced from 50 to account for the new state variable
}
