// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {OnlyOwnersGuard} from "safe-smart-account/contracts/examples/guards/OnlyOwnersGuard.sol";

contract DeployOnlysOwnerGuard is Script {
    function run() external {
        vm.startBroadcast();
        OnlyOwnersGuard guard = new OnlyOwnersGuard();
        vm.stopBroadcast();

        console.log("OnlyOwnerGuard deployed at", address(guard));
    }
}
