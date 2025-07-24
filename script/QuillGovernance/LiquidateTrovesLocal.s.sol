// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LoadContracts} from "../Utils/LoadContracts.sol";

import "../DeployQuillLocal.s.sol";

contract ShutdownBranchLocalScript is DeployQuillLocal, LoadContracts {
    function run(uint256 collIndex, uint256[] memory troveIds) external {
        if (vm.envBytes("DEPLOYER").length == 20) {
            // address
            deployer = vm.envAddress("DEPLOYER");
            vm.startBroadcast(deployer);
        } else {
            // private key
            uint256 privateKey = vm.envUint("DEPLOYER");
            deployer = vm.addr(privateKey);
            vm.startBroadcast(privateKey);
        }

        ManifestContracts memory contracts = _loadContracts();

        contracts.branches[collIndex].troveManager.batchLiquidateTroves(troveIds);

        vm.stopBroadcast();
    }
}
