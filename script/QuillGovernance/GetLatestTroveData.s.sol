// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LoadContracts} from "../Utils/LoadContracts.sol";

import "../DeployQuillLocal.s.sol";

contract GetLatestTroveDataScript is DeployQuillLocal, LoadContracts {
    using Strings for *;
    using StringFormatting for *;

    function run(uint256 collIndex, uint256 troveId) external {
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

        uint256 lastGoodPrice = IPriceFeedTestnet(address(contracts.branches[collIndex].priceFeed)).lastGoodPrice();
        _analyzeIndividualTrove(troveId, contracts.branches[collIndex].troveManager, lastGoodPrice);

        vm.stopBroadcast();
    }

    function _analyzeIndividualTrove(uint256 troveId, ITroveManager troveManager, uint256 lastGoodPrice) private view {
        LatestTroveData memory ltd = troveManager.getLatestTroveData(troveId);
        uint256 ICR = troveManager.getCurrentICR(troveId, lastGoodPrice);

        console.log(string.concat('   troveId:                 ', troveId.toString(), ''));
        console.log(string.concat('   recordedDebt:            ', ltd.recordedDebt.toString(), ""));
        console.log(string.concat('   entireDebt:              ', ltd.entireDebt.toString(), ""));
        console.log(string.concat('   entireColl:              ', ltd.entireColl.toString(), ""));
        console.log(string.concat('   status:                  ', _statusToString(troveManager.getTroveStatus(troveId)), ''));
        console.log(string.concat('   ICR:                     ', ICR.toString(), ""));
        console.log(string.concat('   annualInterestRate:      ', ltd.annualInterestRate.toString(), ""));
        console.log(string.concat('   weightedRecordedDebt:    ', ltd.weightedRecordedDebt.toString(), ""));
        console.log(string.concat('   accruedInterest:         ', ltd.accruedInterest.toString(), ""));
        console.log(string.concat('   lastInterestRateAdjTime: ', ltd.lastInterestRateAdjTime.toString(), ""));
        console.log(string.concat('   block.timestamp:         ', block.timestamp.toString(), ""));

        // address troveOwner = troveManager.troveNFT().ownerOf(troveId);
        // console.log(string.concat('          "owner": "', troveOwner.toHexString(), '"'));
    }

    function _statusToString(ITroveManager.Status status) private pure returns (string memory) {
        if (status == ITroveManager.Status.nonExistent) {
            return "nonExistent";
        } else if (status == ITroveManager.Status.active) {
            return "active";
        } else if (status == ITroveManager.Status.closedByOwner) {
            return "closedByOwner";
        } else if (status == ITroveManager.Status.closedByLiquidation) {
            return "closedByLiquidation";
        } else if (status == ITroveManager.Status.zombie) {
            return "zombie";
        }
        return "unknown";
    }
}

