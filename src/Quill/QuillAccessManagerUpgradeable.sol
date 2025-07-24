// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessManagerUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/manager/AccessManagerUpgradeable.sol";

contract QuillAccessManagerUpgradeable is AccessManagerUpgradeable {
    uint32 public constant ADMIN_ROLE_TIMELOCK = 2 hours;
    uint32 public constant ADMIN_ROLE_GRANT_TIMELOCK = 30 days;

    uint64 public constant EMERGENCY_RESPONDER_ROLE = 1;
    uint64 public constant HIGH_PRIORITY_OPS_ROLE = 2;
    uint64 public constant MEDIUM_PRIORITY_OPS_ROLE = 3;
    uint64 public constant LOW_PRIORITY_OPS_ROLE = 4;

    uint32 public constant HIGH_PRIORITY_TIMELOCK = 5 minutes;
    uint32 public constant MEDIUM_PRIORITY_TIMELOCK = 2 days;
    uint32 public constant LOW_PRIORITY_TIMELOCK = 1 weeks;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __AccessManager_init(admin);
    }

    function minSetback() public pure override returns (uint32) {
        return 0;
    }
}
