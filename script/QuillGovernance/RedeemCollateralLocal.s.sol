// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LoadContracts} from "../Utils/LoadContracts.sol";

import "../DeployQuillLocal.s.sol";

contract RedeemCollateralLocalScript is DeployQuillLocal, LoadContracts {
    function run(uint256 attemptedBoldAmount) external {
        bool interactActorPrivateKeySet = vm.envOr("INTERACT_ACTOR_PRIVATEKEY", bytes("")).length > 0;
        if (interactActorPrivateKeySet) {
            // check INTERACT_ACTOR_PRIVATEKEY first
            uint256 privateKey = vm.envUint("INTERACT_ACTOR_PRIVATEKEY");
            deployer = vm.addr(privateKey);
            vm.startBroadcast(privateKey);
        } else {
            // fallback to DEPLOYER
            bytes memory deployerBytes = vm.envBytes("DEPLOYER");
            if (deployerBytes.length == 20) {
                // address
                deployer = vm.envAddress("DEPLOYER");
                vm.startBroadcast(deployer);
            } else {
                // private key
                uint256 privateKey = vm.envUint("DEPLOYER");
                deployer = vm.addr(privateKey);
                vm.startBroadcast(privateKey);
            }
        }

        ManifestContracts memory contracts = _loadContracts();
        uint256 boldBefore = contracts.boldToken.balanceOf(deployer);
        console.log("Bold balance before (BOLD):", boldBefore);
        console.log("Attempting to redeem (BOLD):", attemptedBoldAmount);

        uint256 maxFeePct = contracts.collateralRegistry.getRedemptionRateForRedeemedAmount(attemptedBoldAmount);
        contracts.collateralRegistry.redeemCollateral(attemptedBoldAmount, 10, maxFeePct);

        uint256 actualBoldAmount = boldBefore - contracts.boldToken.balanceOf(deployer);
        console.log("Actually redeemed (BOLD):", actualBoldAmount);

        vm.stopBroadcast();
    }
}
