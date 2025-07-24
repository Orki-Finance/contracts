// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "src/BoldToken.sol";
import "src/CollateralRegistry.sol";
import "./TestContracts/DevTestSetup.sol";

contract CollateralRegistryTest is DevTestSetup {
    // Testing with already existing contracts to avoid more boilerplate code
    function testAddCollateralRestrictions() public {
        vm.startPrank(addrDeployer);
        vm.expectRevert(CollateralRegistry.InvalidCollateral.selector);
        collateralRegistry.addCollateral(boldToken, troveManager, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addrDeployer);
        vm.expectRevert(CollateralRegistry.InvalidTroveManagerAddresses.selector);
        collateralRegistry.addCollateral(WETH, troveManager, type(uint256).max);
        vm.stopPrank();
    }
}
