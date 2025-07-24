// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ICollateralRegistry} from "src/Interfaces/ICollateralRegistry.sol";
import {IBoldToken} from "src/Interfaces/IBoldToken.sol";
import {IWETH} from "src/Interfaces/IWETH.sol";
import {IHintHelpers} from "src/Interfaces/IHintHelpers.sol";
import {IMultiTroveGetter} from "src/Interfaces/IMultiTroveGetter.sol";
import {IActivePool} from "src/Interfaces/IActivePool.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {ICollSurplusPool} from "src/Interfaces/ICollSurplusPool.sol";
import {IDefaultPool} from "src/Interfaces/IDefaultPool.sol";
import {ISortedTroves} from "src/Interfaces/ISortedTroves.sol";
import {IStabilityPool} from "src/Interfaces/IStabilityPool.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {ITroveNFT} from "src/Interfaces/ITroveNFT.sol";
import {IPriceFeed} from "src/Interfaces/IPriceFeed.sol";
import {IInterestRouter} from "src/Interfaces/IInterestRouter.sol";
import {ILeverageZapper} from "src/Zappers/Interfaces/ILeverageZapper.sol";
import {MetadataNFT} from "src/NFTMetadata/MetadataNFT.sol";
import {GasPool} from "src/GasPool.sol";
import {WETHZapper} from "src/Zappers/WETHZapper.sol";
import {GasCompZapper} from "src/Zappers/GasCompZapper.sol";
import {IAddressesRegistry} from "src/Interfaces/IAddressesRegistry.sol";
import {ISequencerSentinel} from "src/Quill/Interfaces/ISequencerSentinel.sol";
import {QuillAccessManagerUpgradeable} from "src/Quill/QuillAccessManagerUpgradeable.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract LoadContracts is Script {
    struct BranchContracts {
        IAddressesRegistry addressesRegistry;
        IActivePool activePool;
        IBorrowerOperations borrowerOperations;
        ICollSurplusPool collSurplusPool;
        IDefaultPool defaultPool;
        ISortedTroves sortedTroves;
        IStabilityPool stabilityPool;
        ITroveManager troveManager;
        ITroveNFT troveNFT;
        MetadataNFT metadataNFT;
        IPriceFeed priceFeed;
        GasPool gasPool;
        IInterestRouter interestRouter;
        IERC20Metadata collToken;
        WETHZapper wethZapper;
        GasCompZapper gasCompZapper;
        ILeverageZapper leverageZapper;
    }

    struct ManifestContracts {
        ICollateralRegistry collateralRegistry;
        IBoldToken boldToken;
        IWETH weth;
        IHintHelpers hintHelpers;
        IMultiTroveGetter multiTroveGetter;
        ISequencerSentinel sequencerSentinel;
        QuillAccessManagerUpgradeable quillAccessManager;
        BranchContracts[] branches;
    }

    function _loadContracts() internal view returns (ManifestContracts memory) {
        ManifestContracts memory contracts;
        string memory manifestJson;

        try vm.readFile("deployment-manifest.json") returns (string memory content) {
            manifestJson = content;

            contracts.collateralRegistry = ICollateralRegistry(vm.parseJsonAddress(manifestJson, ".collateralRegistry"));
            contracts.boldToken = IBoldToken(vm.parseJsonAddress(manifestJson, ".boldToken"));
            contracts.weth = IWETH(vm.parseJsonAddress(manifestJson, ".branches[0].collToken"));
            contracts.hintHelpers = IHintHelpers(vm.parseJsonAddress(manifestJson, ".hintHelpers"));
            contracts.multiTroveGetter = IMultiTroveGetter(vm.parseJsonAddress(manifestJson, ".multiTroveGetter"));
            contracts.sequencerSentinel = ISequencerSentinel(vm.parseJsonAddress(manifestJson, ".sequencerSentinel"));
            contracts.quillAccessManager =
                QuillAccessManagerUpgradeable(vm.parseJsonAddress(manifestJson, ".quillAccessManager"));

            uint256 branchesLength = contracts.collateralRegistry.totalCollaterals(); //vm.parseJsonUint(manifestJson, ".branches.length");
            contracts.branches = new BranchContracts[](branchesLength);

            for (uint256 i = 0; i < branchesLength; i++) {
                string memory branchPath = string(abi.encodePacked(".branches[", vm.toString(i), "]"));

                contracts.branches[i] = BranchContracts({
                    addressesRegistry: IAddressesRegistry(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".addressesRegistry")))
                    ),
                    activePool: IActivePool(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".activePool")))
                    ),
                    borrowerOperations: IBorrowerOperations(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".borrowerOperations")))
                    ),
                    collSurplusPool: ICollSurplusPool(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".collSurplusPool")))
                    ),
                    defaultPool: IDefaultPool(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".defaultPool")))
                    ),
                    sortedTroves: ISortedTroves(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".sortedTroves")))
                    ),
                    stabilityPool: IStabilityPool(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".stabilityPool")))
                    ),
                    troveManager: ITroveManager(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".troveManager")))
                    ),
                    troveNFT: ITroveNFT(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".troveNFT")))
                    ),
                    metadataNFT: MetadataNFT(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".metadataNFT")))
                    ),
                    priceFeed: IPriceFeed(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".priceFeed")))
                    ),
                    gasPool: GasPool(vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".gasPool")))),
                    interestRouter: IInterestRouter(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".interestRouter")))
                    ),
                    collToken: IERC20Metadata(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".collToken")))
                    ),
                    wethZapper: WETHZapper(
                        payable(vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".wethZapper"))))
                    ),
                    gasCompZapper: GasCompZapper(
                        payable(vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".gasCompZapper"))))
                    ),
                    leverageZapper: ILeverageZapper(
                        vm.parseJsonAddress(manifestJson, string(abi.encodePacked(branchPath, ".leverageZapper")))
                    )
                });
            }
        } catch {}

        return contracts;
    }
}
