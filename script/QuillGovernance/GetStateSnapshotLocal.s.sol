// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LoadContracts} from "../Utils/LoadContracts.sol";
import {LiquityMath} from "src/Dependencies/LiquityMath.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {StringFormatting} from "../../test/Utils/StringFormatting.sol";
import "../DeployQuillLocal.s.sol";

contract GetStateSnapshotLocalScript is DeployQuillLocal, LoadContracts {
    using Strings for *;
    using StringFormatting for *;

    string constant file = "protocolSnapshot.json";
    //record all owners
    address[] owners;
    mapping(address => bool) ownerSet;

    struct TroveConfig {
        uint256 CCR;
        uint256 MCR;
        uint256 SCR;
        uint256 LIQUIDATION_PENALTY_SP;
        uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
        uint256 MIN_DEBT;
        uint256 SP_YIELD_SPLIT;
        uint256 minAnnualInterestRate;
    }

    function _addOwnerToSet(address owner) private {
        if (!ownerSet[owner]) {
            ownerSet[owner] = true;
            owners.push(owner);
        }
    }

    function _getOwnersQuillBalance(ManifestContracts memory contracts) private {
        vm.writeLine(file, '  "owners": [');
        for (uint256 i = 0; i < owners.length; i++) {
            vm.writeLine(file, "    {");
            vm.writeLine(file, string.concat('      "address": "', owners[i].toHexString(), '",'));
            vm.writeLine(
                file, string.concat('      "usdqBalance": ', contracts.boldToken.balanceOf(owners[i]).toString(), ",")
            );
            vm.writeLine(file, string.concat('      "collaterals": ['));
            for (uint256 j = 0; j < contracts.collateralRegistry.totalCollaterals(); j++) {
                vm.writeLine(file, "        {");
                vm.writeLine(file, string.concat('          "index": ', j.toString(), ","));
                vm.writeLine(
                    file,
                    string.concat('          "symbol": "', contracts.collateralRegistry.getToken(j).symbol(), '",')
                );
                vm.writeLine(
                    file,
                    string.concat(
                        '          "balance": ',
                        contracts.collateralRegistry.getToken(j).balanceOf(owners[i]).toString()
                    )
                );
                if (j < contracts.collateralRegistry.totalCollaterals() - 1) {
                    vm.writeLine(file, "        },");
                } else {
                    vm.writeLine(file, "        }");
                }
            }
            vm.writeLine(file, "      ]");
            if (i < owners.length - 1) {
                vm.writeLine(file, "    },");
            } else {
                vm.writeLine(file, "    }");
            }
        }
        vm.writeLine(file, "  ],");
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

    function _analyzeIndividualTrove(uint256 troveId, ITroveManager troveManager, uint256 lastGoodPrice) private {
        LatestTroveData memory ltd = troveManager.getLatestTroveData(troveId);
        uint256 ICR = troveManager.getCurrentICR(troveId, lastGoodPrice);

        vm.writeLine(file, string.concat('          "troveId": "', troveId.toString(), '",'));
        vm.writeLine(file, string.concat('          "entireDebt": ', ltd.entireDebt.toString(), ","));
        vm.writeLine(file, string.concat('          "entireColl": ', ltd.entireColl.toString(), ","));
        vm.writeLine(
            file, string.concat('          "status": "', _statusToString(troveManager.getTroveStatus(troveId)), '",')
        );
        vm.writeLine(file, string.concat('          "ICR": ', ICR.toString(), ","));
        vm.writeLine(file, string.concat('          "annualInterestRate": ', ltd.annualInterestRate.toString(), ","));

        address troveOwner = troveManager.troveNFT().ownerOf(troveId);
        vm.writeLine(file, string.concat('          "owner": "', troveOwner.toHexString(), '"'));
        _addOwnerToSet(troveOwner);
    }

    function _analyzeStabilityPool(IStabilityPool _stabilityPool) private {
        vm.writeLine(file, '      "stabilityPool": {');
        vm.writeLine(
            file, string.concat('        "totalDeposits": ', _stabilityPool.getTotalBoldDeposits().toString(), ",")
        );
        vm.writeLine(
            file, string.concat('        "yieldGainsPending": ', _stabilityPool.getYieldGainsPending().toString(), ",")
        );
        vm.writeLine(
            file, string.concat('        "yieldGainsOwed": ', _stabilityPool.getYieldGainsOwed().toString(), ",")
        );
        vm.writeLine(file, string.concat('        "collBalance": ', _stabilityPool.getCollBalance().toString()));
        vm.writeLine(file, "      },");
    }

    function _analyzeActivePool(IActivePool _activePool) private {
        vm.writeLine(file, '      "activePool": {');
        vm.writeLine(file, string.concat('        "totalCollateral": ', _activePool.getCollBalance().toString(), ","));
        vm.writeLine(file, string.concat('        "boldDebt": ', _activePool.getBoldDebt().toString(), ","));
        vm.writeLine(file, string.concat('        "lastAggUpdateTime": ', _activePool.lastAggUpdateTime().toString()));
        vm.writeLine(file, "      },");
    }

    function _analyzeDefaultPool(IDefaultPool _defaultPool) private {
        vm.writeLine(file, '      "defaultPool": {');
        vm.writeLine(file, string.concat('        "totalCollateral": ', _defaultPool.getCollBalance().toString(), ","));
        vm.writeLine(file, string.concat('        "boldDebt": ', _defaultPool.getBoldDebt().toString()));
        vm.writeLine(file, "      },");
    }

    function _analyzeCollSurplusPool(ICollSurplusPool _collSurplusPool) private {
        vm.writeLine(file, '      "collSurplusPool": {');
        vm.writeLine(file, string.concat('        "totalSurplus": ', _collSurplusPool.getCollBalance().toString()));
        vm.writeLine(file, "      },");
    }

    function _analyzeTroveManager(BranchContracts memory branchContracts, ITroveManager troveManager) private {
        uint256 lastGoodPrice = IPriceFeedTestnet(address(branchContracts.priceFeed)).lastGoodPrice();
        uint256 totalTroveIds = troveManager.getTroveIdsCount();
        vm.writeLine(file, string.concat('      "totalTroves": ', totalTroveIds.toString(), ","));
        uint256 branchDebt = troveManager.getEntireBranchDebt();
        vm.writeLine(file, string.concat('      "totalDebt": ', branchDebt.toString(), ","));
        uint256 branchColl = troveManager.getEntireBranchColl();
        vm.writeLine(file, string.concat('      "totalCollateral": ', branchColl.toString(), ","));
        uint256 TCR = LiquityMath._computeCR(branchColl, branchDebt, lastGoodPrice);
        vm.writeLine(file, string.concat('      "TCR": ', TCR.toString(), ","));
        IStabilityPool stabilityPool = troveManager.stabilityPool();
        vm.writeLine(
            file, string.concat('      "totalSPDeposits": ', stabilityPool.getTotalBoldDeposits().toString(), ",")
        );
        vm.writeLine(file, string.concat('      "shutdownTime": ', troveManager.shutdownTime().toString(), ","));
        TroveConfig memory config = TroveConfig(
            troveManager.CCR(),
            troveManager.MCR(),
            troveManager.SCR(),
            troveManager.liquidationPenaltySP(),
            troveManager.liquidationPenaltyRedistribution(),
            troveManager.MIN_DEBT(),
            branchContracts.activePool.stabilityPoolYieldSplit(),
            troveManager.minAnnualInterestRate()
        );

        vm.writeLine(file, string.concat('      "CCR": ', config.CCR.toString(), ","));
        vm.writeLine(file, string.concat('      "MCR": ', config.MCR.toString(), ","));
        vm.writeLine(file, string.concat('      "SCR": ', config.SCR.toString(), ","));
        vm.writeLine(
            file, string.concat('      "liquidationPenaltySP": ', config.LIQUIDATION_PENALTY_SP.toString(), ",")
        );
        vm.writeLine(
            file,
            string.concat(
                '      "liquidationPenaltyRedistribution": ', config.LIQUIDATION_PENALTY_REDISTRIBUTION.toString(), ","
            )
        );
        vm.writeLine(file, string.concat('      "minDebt": ', config.MIN_DEBT.toString(), ","));
        vm.writeLine(file, string.concat('      "SPYieldSplit": ', config.SP_YIELD_SPLIT.toString(), ","));
        vm.writeLine(
            file, string.concat('      "minAnnualInterestRate": ', config.minAnnualInterestRate.toString(), ",")
        );
        vm.writeLine(file, string.concat('      "lastGoodPrice": ', lastGoodPrice.toString(), ","));

        _analyzeStabilityPool(branchContracts.stabilityPool);
        _analyzeActivePool(branchContracts.activePool);
        _analyzeDefaultPool(branchContracts.defaultPool);
        _analyzeCollSurplusPool(branchContracts.collSurplusPool);

        vm.writeLine(file, '      "troves": [');
        for (uint256 i = 0; i < totalTroveIds; i++) {
            vm.writeLine(file, "        {");
            _analyzeIndividualTrove(troveManager.getTroveFromTroveIdsArray(i), troveManager, lastGoodPrice);
            if (i < totalTroveIds - 1) {
                vm.writeLine(file, "        },");
            } else {
                vm.writeLine(file, "        }");
            }
        }
        vm.writeLine(file, "      ]");
    }

    function _protocolConfig() private {
        vm.writeLine(file, '  "protocolConfig": {');
        vm.writeLine(file, string.concat('    "decimalPrecision": ', DECIMAL_PRECISION.toString(), ","));
        vm.writeLine(file, string.concat('    "onePercent": ', _1pct.toString(), ","));
        vm.writeLine(file, string.concat('    "oneHundredPercent": ', _100pct.toString(), ","));
        vm.writeLine(file, string.concat('    "ethGasCompensation": ', ETH_GAS_COMPENSATION.toString()));
        vm.writeLine(file, "  }");
    }

    function run() external override {
        ManifestContracts memory contracts = _loadContracts();
        vm.writeFile(file, "{\n");
        vm.writeLine(file, string.concat('  "totalSupply": ', contracts.boldToken.totalSupply().toString(), ","));

        uint256 totalCollaterals = contracts.collateralRegistry.totalCollaterals();
        vm.writeLine(file, string.concat('  "numberBranches": ', totalCollaterals.toString(), ","));
        vm.writeLine(file, string.concat('  "timestamp": ', block.timestamp.toString(), ","));
        vm.writeLine(file, string.concat('  "block": ', block.number.toString(), ","));

        vm.writeLine(file, '  "branches": [');
        for (uint256 i = 0; i < totalCollaterals; i++) {
            IERC20Metadata collateral = contracts.collateralRegistry.getToken(i);
            vm.writeLine(file, "    {");
            vm.writeLine(file, string.concat('      "index": ', i.toString(), ","));
            vm.writeLine(file, string.concat('      "collateral": "', collateral.name(), '",'));
            vm.writeLine(file, string.concat('      "symbol": "', collateral.symbol(), '",'));
            vm.writeLine(file, string.concat('      "decimals": "', collateral.decimals().toString(), '",'));

            ITroveManager troveManager = contracts.collateralRegistry.getTroveManager(i);
            _analyzeTroveManager(contracts.branches[i], troveManager);
            if (i < totalCollaterals - 1) {
                vm.writeLine(file, "    },");
            } else {
                vm.writeLine(file, "    }");
            }
        }
        vm.writeLine(file, "  ],");
        _getOwnersQuillBalance(contracts);
        _protocolConfig();
        vm.writeLine(file, "}");
    }
}
