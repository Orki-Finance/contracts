// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import "./Dependencies/Ownable.sol";
import {MIN_LIQUIDATION_PENALTY_SP, MAX_LIQUIDATION_PENALTY_REDISTRIBUTION} from "./Dependencies/Constants.sol";
import "./Interfaces/IAddressesRegistry.sol";
import "openzeppelin-contracts/contracts/access/manager/AccessManaged.sol";

contract AddressesRegistry is IAddressesRegistry, AccessManaged {
    IERC20Metadata public collToken;
    IBorrowerOperations public borrowerOperations;
    ITroveManager public troveManager;
    ITroveNFT public troveNFT;
    IMetadataNFT public metadataNFT;
    IStabilityPool public stabilityPool;
    IPriceFeed public priceFeed;
    IActivePool public activePool;
    IDefaultPool public defaultPool;
    address public gasPoolAddress;
    ICollSurplusPool public collSurplusPool;
    ISortedTroves public sortedTroves;
    IInterestRouter public interestRouter;
    IHintHelpers public hintHelpers;
    IMultiTroveGetter public multiTroveGetter;
    ICollateralRegistry public collateralRegistry;
    IBoldToken public boldToken;
    ISequencerSentinel public sequencerSentinel;
    IWETH public WETH;

    // Liquidation penalty for troves offset to the SP
    uint256 public immutable LIQUIDATION_PENALTY_SP;
    // Liquidation penalty for troves redistributed
    uint256 public immutable LIQUIDATION_PENALTY_REDISTRIBUTION;

    error SPPenaltyTooLow();
    error SPPenaltyGtRedist();
    error RedistPenaltyTooHigh();
    error AddressesAlreadySet();

    event CollTokenAddressChanged(address _collTokenAddress);
    event BorrowerOperationsAddressChanged(address _borrowerOperationsAddress);
    event TroveManagerAddressChanged(address _troveManagerAddress);
    event TroveNFTAddressChanged(address _troveNFTAddress);
    event MetadataNFTAddressChanged(address _metadataNFTAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event PriceFeedAddressChanged(address _priceFeedAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event InterestRouterAddressChanged(address _interestRouterAddress);
    event HintHelpersAddressChanged(address _hintHelpersAddress);
    event MultiTroveGetterAddressChanged(address _multiTroveGetterAddress);
    event CollateralRegistryAddressChanged(address _collateralRegistryAddress);
    event BoldTokenAddressChanged(address _boldTokenAddress);
    event WETHAddressChanged(address _wethAddress);
    event SequencerSentinelAddressChanged(address _sequencerSentinelAddress);

    constructor(address _authority, uint256 _liquidationPenaltySP, uint256 _liquidationPenaltyRedistribution)
        AccessManaged(_authority)
    {
        if (_liquidationPenaltySP < MIN_LIQUIDATION_PENALTY_SP) revert SPPenaltyTooLow();
        if (_liquidationPenaltySP > _liquidationPenaltyRedistribution) revert SPPenaltyGtRedist();
        if (_liquidationPenaltyRedistribution > MAX_LIQUIDATION_PENALTY_REDISTRIBUTION) revert RedistPenaltyTooHigh();

        LIQUIDATION_PENALTY_SP = _liquidationPenaltySP;
        LIQUIDATION_PENALTY_REDISTRIBUTION = _liquidationPenaltyRedistribution;
    }

    function stabilityPoolYieldSplit() public view override returns (uint256) {
        return activePool.stabilityPoolYieldSplit();
    }

    function CCR() public view returns (uint256) {
        return troveManager.CCR();
    }

    function SCR() public view returns (uint256) {
        return troveManager.SCR();
    }

    function MCR() public view returns (uint256) {
        return troveManager.MCR();
    }

    function BCR() public view returns (uint256) {
        return troveManager.BCR();
    }

    function setAddresses(AddressVars memory _vars) external restricted {
        if (address(WETH) != address(0)) revert AddressesAlreadySet();

        collToken = _vars.collToken;
        borrowerOperations = _vars.borrowerOperations;
        troveManager = _vars.troveManager;
        troveNFT = _vars.troveNFT;
        metadataNFT = _vars.metadataNFT;
        stabilityPool = _vars.stabilityPool;
        priceFeed = _vars.priceFeed;
        activePool = _vars.activePool;
        defaultPool = _vars.defaultPool;
        gasPoolAddress = _vars.gasPoolAddress;
        collSurplusPool = _vars.collSurplusPool;
        sortedTroves = _vars.sortedTroves;
        interestRouter = _vars.interestRouter;
        hintHelpers = _vars.hintHelpers;
        multiTroveGetter = _vars.multiTroveGetter;
        collateralRegistry = _vars.collateralRegistry;
        boldToken = _vars.boldToken;
        sequencerSentinel = _vars.sequencerSentinel;
        WETH = _vars.WETH;

        emit CollTokenAddressChanged(address(_vars.collToken));
        emit BorrowerOperationsAddressChanged(address(_vars.borrowerOperations));
        emit TroveManagerAddressChanged(address(_vars.troveManager));
        emit TroveNFTAddressChanged(address(_vars.troveNFT));
        emit MetadataNFTAddressChanged(address(_vars.metadataNFT));
        emit StabilityPoolAddressChanged(address(_vars.stabilityPool));
        emit PriceFeedAddressChanged(address(_vars.priceFeed));
        emit ActivePoolAddressChanged(address(_vars.activePool));
        emit DefaultPoolAddressChanged(address(_vars.defaultPool));
        emit GasPoolAddressChanged(_vars.gasPoolAddress);
        emit CollSurplusPoolAddressChanged(address(_vars.collSurplusPool));
        emit SortedTrovesAddressChanged(address(_vars.sortedTroves));
        emit InterestRouterAddressChanged(address(_vars.interestRouter));
        emit HintHelpersAddressChanged(address(_vars.hintHelpers));
        emit MultiTroveGetterAddressChanged(address(_vars.multiTroveGetter));
        emit CollateralRegistryAddressChanged(address(_vars.collateralRegistry));
        emit BoldTokenAddressChanged(address(_vars.boldToken));
        emit WETHAddressChanged(address(_vars.WETH));
        emit SequencerSentinelAddressChanged(address(_vars.sequencerSentinel));
    }
}
