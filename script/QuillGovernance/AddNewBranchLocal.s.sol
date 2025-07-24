// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Faucet} from "../../test/TestContracts/ERC20Faucet.sol";
import {LoadContracts} from "../Utils/LoadContracts.sol";

import "../DeployQuillLocal.s.sol";

contract AddNewBranchLocalScript is DeployQuillLocal, LoadContracts {
    function _createToken() private returns (IERC20Metadata newCollToken) {
        newCollToken = new ERC20Faucet(
            "New Collateral", // _name
            "NC", // _symbol
            100 ether, //     _tapAmount
            1 days //         _tapPeriod
        );
    }

    function run() external override {
        SALT = keccak256(abi.encodePacked(block.timestamp));

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

        IERC20Metadata newCollToken = _createToken();
        ManifestContracts memory contracts = _loadContracts();
        TroveManagerParams memory troveManagerParams = TroveManagerParams(
            150e16, // CCR
            110e16, // MCR
            110e16, // SCR
            10e16, // BR
            5e16, // LIQUIDATION_PENALTY_SP
            10e16, // LIQUIDATION_PENALTY_REDISTRIBUTION
            2000e18, // MIN_DEBT
            72e16, // SP_YIELD_SPLIT
            _1pct / 2, // minAnnualInterestRate
            type(uint256).max
        );

        (IAddressesRegistry addressesRegistry, address troveManagerAddress) =
            _deployAddressesRegistry(troveManagerParams, contracts.quillAccessManager);

        Contracts memory branchContracts = _deployAndConnectCollateralContracts(
            ERC20Faucet(address(newCollToken)),
            contracts.boldToken,
            contracts.collateralRegistry,
            contracts.weth,
            addressesRegistry,
            troveManagerAddress,
            contracts.hintHelpers,
            contracts.multiTroveGetter,
            contracts.sequencerSentinel,
            troveManagerParams
        );
        IPriceFeedTestnet(address(branchContracts.priceFeed)).setPrice(2_000 ether);

        contracts.collateralRegistry.addCollateral(newCollToken, branchContracts.troveManager, UNLIMITED_BORROW_CAP);

        vm.stopBroadcast();
    }
}
