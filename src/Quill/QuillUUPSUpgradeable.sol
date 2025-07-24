// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/manager/AccessManagedUpgradeable.sol";

abstract contract QuillUUPSUpgradeable is Initializable, UUPSUpgradeable, AccessManagedUpgradeable {
    /// @param _authority Must be the address of the QuillAccessManager instance
    function __QuillUUPSUpgradeable_init(address _authority) internal onlyInitializing {
        __AccessManaged_init(_authority);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    uint256[50] private __gap;
}
