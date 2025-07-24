// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../TestContracts/DevTestSetup.sol";
import {TestDeployer} from "../TestContracts/Deployment.t.sol";
import {MAX_NUMBER_COLLATERALS} from "src/Dependencies/Constants.sol";
import "src/CollateralRegistry.sol";
import {ERC20Faucet} from "../TestContracts/ERC20Faucet.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import "src/AddressesRegistry.sol";
import "../TestContracts/MockInterestRouter.sol";
import "src/ActivePool.sol";
import "src/BoldToken.sol";
import "src/BorrowerOperations.sol";
import "src/CollSurplusPool.sol";
import "src/DefaultPool.sol";
import "src/GasPool.sol";
import "src/HintHelpers.sol";
import "src/MultiTroveGetter.sol";
import "src/SortedTroves.sol";
import "src/StabilityPool.sol";
import "../TestContracts/BorrowerOperationsTester.t.sol";
import "../TestContracts/TroveManagerTester.t.sol";
import "src/TroveNFT.sol";
import "src/NFTMetadata/MetadataNFT.sol";
import "src/Zappers/Modules/Exchanges/Curve/ICurveStableswapNGPool.sol";

// import {QuillAccessManagerUpgradeable} from "../../Quill/QuillAccessManagerUpgradeable.sol";

contract GoverningCollateralsTest is DevTestSetup, TestDeployer {
    function _createToken() private returns (IERC20Metadata newCollToken) {
        newCollToken = new ERC20Faucet(
            "New Collateral", // _name
            "NC", // _symbol
            100 ether, //     _tapAmount
            1 days //         _tapPeriod
        );
    }

    function _deployAddressesRegistryAdd(
        TroveManagerParams memory _troveManagerParams,
        QuillAccessManagerUpgradeable _quillAccessManager
    ) internal returns (IAddressesRegistry, address) {
        vm.startPrank(addrDeployer);
        IAddressesRegistry newAddressesRegistry = new AddressesRegistry(
            address(_quillAccessManager),
            _troveManagerParams.LIQUIDATION_PENALTY_SP,
            _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        address troveManagerAddress = getAddress(
            addrDeployer,
            getBytecode(type(TroveManagerTester).creationCode, address(newAddressesRegistry), _troveManagerParams),
            SALT
        );
        vm.stopPrank();
        return (newAddressesRegistry, troveManagerAddress);
    }

    function _deployAndConnectCollateralContractsAdd(
        IERC20Metadata _collToken,
        IAddressesRegistry _addressesRegistry,
        address _troveManagerAddress,
        TroveManagerParams memory _troveManagerParams
    ) internal returns (LiquityContractsDev memory contracts, Zappers memory zappers) {
        vm.startPrank(addrDeployer);
        LiquityContractAddresses memory addresses;
        contracts.collToken = _collToken;

        // Deploy all contracts, using testers for TM and PriceFeed
        contracts.addressesRegistry = _addressesRegistry;
        contracts.priceFeed = new PriceFeedTestnet();
        contracts.interestRouter = new MockInterestRouter();

        // Deploy Metadata
        MetadataNFT newMetadataNFT = deployMetadata(SALT, _collToken.symbol());
        addresses.metadataNFT = getAddress(
            addrDeployer, getBytecode(type(MetadataNFT).creationCode, address(initializedFixedAssetReader)), SALT
        );
        assert(address(newMetadataNFT) == addresses.metadataNFT);

        // Pre-calc addresses
        addresses.borrowerOperations = getAddress(
            addrDeployer,
            getBytecode(type(BorrowerOperationsTester).creationCode, address(contracts.addressesRegistry)),
            SALT
        );
        addresses.troveManager = _troveManagerAddress;
        addresses.troveNFT = getAddress(
            addrDeployer, getBytecode(type(TroveNFT).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.stabilityPool = getAddress(
            addrDeployer, getBytecode(type(StabilityPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.activePool = getAddress(
            addrDeployer,
            getBytecode(
                type(ActivePool).creationCode, address(contracts.addressesRegistry), _troveManagerParams.SP_YIELD_SPLIT
            ),
            SALT
        );
        addresses.defaultPool = getAddress(
            addrDeployer, getBytecode(type(DefaultPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.gasPool = getAddress(
            addrDeployer, getBytecode(type(GasPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.collSurplusPool = getAddress(
            addrDeployer, getBytecode(type(CollSurplusPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.sortedTroves = getAddress(
            addrDeployer, getBytecode(type(SortedTroves).creationCode, address(contracts.addressesRegistry)), SALT
        );

        // Deploy contracts
        IAddressesRegistry.AddressVars memory addressVars = IAddressesRegistry.AddressVars({
            collToken: _collToken,
            borrowerOperations: IBorrowerOperations(addresses.borrowerOperations),
            troveManager: ITroveManager(addresses.troveManager),
            troveNFT: ITroveNFT(addresses.troveNFT),
            metadataNFT: IMetadataNFT(addresses.metadataNFT),
            stabilityPool: IStabilityPool(addresses.stabilityPool),
            priceFeed: contracts.priceFeed,
            activePool: IActivePool(addresses.activePool),
            defaultPool: IDefaultPool(addresses.defaultPool),
            gasPoolAddress: addresses.gasPool,
            collSurplusPool: ICollSurplusPool(addresses.collSurplusPool),
            sortedTroves: ISortedTroves(addresses.sortedTroves),
            interestRouter: contracts.interestRouter,
            hintHelpers: hintHelpers,
            multiTroveGetter: multiTroveGetter,
            collateralRegistry: collateralRegistry,
            sequencerSentinel: sequencerSentinel,
            boldToken: boldToken,
            WETH: WETH
        });
        contracts.addressesRegistry.setAddresses(addressVars);

        contracts.borrowerOperations = new BorrowerOperationsTester{salt: SALT}(contracts.addressesRegistry);
        contracts.troveManager = new TroveManagerTester{salt: SALT}(
            contracts.addressesRegistry,
            _troveManagerParams.CCR,
            _troveManagerParams.MCR,
            _troveManagerParams.SCR,
            _troveManagerParams.BCR,
            _troveManagerParams.MIN_DEBT,
            _troveManagerParams.minAnnualInterestRate,
            _troveManagerParams.LIQUIDATION_PENALTY_SP,
            _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        contracts.troveNFT = new TroveNFT{salt: SALT}(contracts.addressesRegistry);
        contracts.stabilityPool = new StabilityPool{salt: SALT}(contracts.addressesRegistry);
        contracts.activePool =
            new ActivePool{salt: SALT}(contracts.addressesRegistry, _troveManagerParams.SP_YIELD_SPLIT);
        contracts.pools.defaultPool = new DefaultPool{salt: SALT}(contracts.addressesRegistry);
        contracts.pools.gasPool = new GasPool{salt: SALT}(contracts.addressesRegistry);
        contracts.pools.collSurplusPool = new CollSurplusPool{salt: SALT}(contracts.addressesRegistry);
        contracts.sortedTroves = new SortedTroves{salt: SALT}(contracts.addressesRegistry);

        assert(address(contracts.borrowerOperations) == addresses.borrowerOperations);
        assert(address(contracts.troveManager) == addresses.troveManager);
        assert(address(contracts.troveNFT) == addresses.troveNFT);
        assert(address(contracts.stabilityPool) == addresses.stabilityPool);
        assert(address(contracts.activePool) == addresses.activePool);
        assert(address(contracts.pools.defaultPool) == addresses.defaultPool);
        assert(address(contracts.pools.gasPool) == addresses.gasPool);
        assert(address(contracts.pools.collSurplusPool) == addresses.collSurplusPool);
        assert(address(contracts.sortedTroves) == addresses.sortedTroves);

        // deploy zappers
        _deployZappers(
            contracts.addressesRegistry,
            contracts.collToken,
            boldToken,
            WETH,
            contracts.priceFeed,
            ICurveStableswapNGPool(address(0)),
            false,
            zappers
        );
        vm.stopPrank();
    }

    function _generateNewBranch() private returns (LiquityContractsDev memory) {
        // create a new erc20 token
        IERC20Metadata newCollToken = _createToken();

        TroveManagerParams memory tmparams = TroveManagerParams(
            150e16,
            110e16,
            110e16,
            10e16,
            5e16,
            10e16,
            300e18,
            50e16,
            _1pct / 2
        );

        (IAddressesRegistry newAddressesRegistry, address troveManagerAddress) =
            _deployAddressesRegistryAdd(tmparams, quillAccessManager);

        (LiquityContractsDev memory contracts, /* Zappers memory zappers */ ) =
            _deployAndConnectCollateralContractsAdd(newCollToken, newAddressesRegistry, troveManagerAddress, tmparams);

        uint256 initialCollateralAmount = 10_000e18;
        for (uint256 i = 0; i < 4; i++) {
            // A to D
            giveAndApproveCollateral(
                newCollToken, accountsList[i], initialCollateralAmount, address(contracts.borrowerOperations)
            );
            // Approve WETH for gas compensation in all branches
            vm.startPrank(accountsList[i]);
            WETH.approve(address(contracts.borrowerOperations), type(uint256).max);
            vm.stopPrank();
        }

        return contracts;
    }

    function testAddCollateral() public {
        LiquityContractsDev memory newBranchContracts = _generateNewBranch();
        vm.startPrank(A);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, A));
        collateralRegistry.addCollateral(newBranchContracts.collToken, newBranchContracts.troveManager, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addrDeployer);
        collateralRegistry.addCollateral(newBranchContracts.collToken, newBranchContracts.troveManager, type(uint256).max);
        vm.stopPrank();

        // todo: add additional verifications
    }

    function testCappedCollateral() public {
        LiquityContractsDev memory newBranchContracts = _generateNewBranch();

        newBranchContracts.priceFeed.setPrice(2000e18);
        uint256 borrowAmount = 20200e18;
        uint256 cappedAmount = borrowAmount * 3 + 200e18; //allows for 3 new troves of borrowAmount plus a bit of interest

        vm.startPrank(addrDeployer);
        collateralRegistry.addCollateral(newBranchContracts.collToken, newBranchContracts.troveManager, cappedAmount);
        vm.stopPrank();

        uint256 boldInitialSupply = boldToken.totalSupply();

        _openTroveHelper(A, 0, 20 ether, borrowAmount, 1e17, newBranchContracts.borrowerOperations);
        _openTroveHelper(B, 0, 20 ether, borrowAmount, 2e17, newBranchContracts.borrowerOperations);
        _openTroveHelper(C, 0, 20 ether, borrowAmount, 3e17, newBranchContracts.borrowerOperations);

        uint256 upfrontFee = predictOpenTroveUpfrontFee(borrowAmount, 4e17);
        vm.startPrank(D);

        vm.expectRevert(abi.encodeWithSelector(BoldToken.OverBranchCapLimit.selector, newBranchContracts.troveManager));
        newBranchContracts.borrowerOperations.openTrove(
            D,
            0,
            20 ether,
            borrowAmount,
            0, // _upperHint
            0, // _lowerHint
            4e17,
            upfrontFee,
            address(0),
            address(0),
            address(0)
        );
        vm.stopPrank();

        uint256 boldAfter = boldToken.totalSupply();
        vm.assertGt(boldAfter, boldInitialSupply+(borrowAmount*3), "Should have minted 3 open troves and rejected last");

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(addrDeployer);
        collateralRegistry.setSPYieldSplit(1, 70e16);
        vm.stopPrank();

        boldAfter = boldToken.totalSupply();
        vm.assertGt(boldAfter, cappedAmount, "Interest is allowed to grow over cap limit");
    }

    function _openTroveHelper(
        address _account,
        uint256 _index,
        uint256 _coll,
        uint256 _boldAmount,
        uint256 _annualInterestRate,
        IBorrowerOperations _borrowerOperations
    ) private {
        uint256 upfrontFee = predictOpenTroveUpfrontFee(_boldAmount, _annualInterestRate);

        vm.startPrank(_account);

        _borrowerOperations.openTrove(
            _account,
            _index,
            _coll,
            _boldAmount,
            0, // _upperHint
            0, // _lowerHint
            _annualInterestRate,
            upfrontFee,
            address(0),
            address(0),
            address(0)
        );

        vm.stopPrank();
    }

    function _setupForRedemptionM(
        ABCDEF memory _troveInterestRates,
        IBorrowerOperations _borrowerOperations,
        IPriceFeedTestnet _priceFeed
    ) internal {
        _priceFeed.setPrice(2000e18);

        // fast-forward to pass bootstrap phase
        vm.warp(block.timestamp + 14 days);

        _openTroveHelper(A, 0, 20 ether, 20200e18, _troveInterestRates.A, _borrowerOperations);
        _openTroveHelper(B, 0, 20 ether, 20200e18, _troveInterestRates.B, _borrowerOperations);
        _openTroveHelper(C, 0, 20 ether, 20200e18, _troveInterestRates.C, _borrowerOperations);
        _openTroveHelper(D, 0, 20 ether, 20200e18, _troveInterestRates.D, _borrowerOperations);

        // instead of sending to E as the original, we send to F
        transferBold(A, F, boldToken.balanceOf(A));
        transferBold(B, F, boldToken.balanceOf(B));
        transferBold(C, F, boldToken.balanceOf(C));
        transferBold(D, F, boldToken.balanceOf(D));
    }

    function _setupForRedemptionAscendingInterestM(LiquityContractsDev[] memory newListBranchContracts) internal {
        ABCDEF memory troveInterestRates;
        troveInterestRates.A = 1e17; // 10%
        troveInterestRates.B = 2e17; // 20%
        troveInterestRates.C = 3e17; // 30%
        troveInterestRates.D = 4e17; // 40%

        for (uint256 i = 0; i < newListBranchContracts.length; i++) {
            _setupForRedemptionM(
                troveInterestRates, newListBranchContracts[i].borrowerOperations, newListBranchContracts[i].priceFeed
            );
        }
    }

    function _getCollateralAggValueOfUserAssets(address _user) private view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < collateralRegistry.totalCollaterals(); i++) {
            IERC20Metadata _collToken = collateralRegistry.getToken(i);
            ITroveManagerTester _troveManager = ITroveManagerTester(address(collateralRegistry.getTroveManager(i)));
            IPriceFeedTestnet _priceFeed = IPriceFeedTestnet(_troveManager.getPriceAddress());
            uint256 collAmount = _collToken.balanceOf(_user);
            uint256 collValue = collAmount * _priceFeed.getPrice();
            totalCollateralValue += collValue;
        }
        return totalCollateralValue;
    }

    function _redeemHalfOfUsersBalance(address _user)
        private
        returns (uint256 balanceToRedeem, uint256 userTotalCollateralValueBefore)
    {
        balanceToRedeem = boldToken.balanceOf(_user) / 2;
        vm.prank(_user);
        collateralRegistry.redeemCollateral(balanceToRedeem, MAX_UINT256, 1e18);
        userTotalCollateralValueBefore = _getCollateralAggValueOfUserAssets(_user);
    }

    function testRedeemAfterAddMultipleCols(uint256 gap) public {
        uint256 currentNumberCollaterals = collateralRegistry.totalCollaterals();
        gap = bound(gap, 0, MAX_NUMBER_COLLATERALS - currentNumberCollaterals);
        _setupForRedemptionAscendingInterest();

        uint256 snapshot = vm.snapshotState();

        (uint256 balanceToRedeemBefore, uint256 userETotalCollateralValueBefore) = _redeemHalfOfUsersBalance(E);

        vm.revertToState(snapshot);

        // to test different amount of collaterals
        LiquityContractsDev[] memory newListBranchContracts =
            new LiquityContractsDev[](MAX_NUMBER_COLLATERALS - currentNumberCollaterals - gap);
        for (uint256 i = currentNumberCollaterals; i < MAX_NUMBER_COLLATERALS - gap; i++) {
            LiquityContractsDev memory newBranchContracts = _generateNewBranch();

            vm.startPrank(addrDeployer);
            collateralRegistry.addCollateral(newBranchContracts.collToken, newBranchContracts.troveManager, type(uint256).max);
            vm.stopPrank();

            newListBranchContracts[i - currentNumberCollaterals] = newBranchContracts;
        }
        _setupForRedemptionAscendingInterestM(newListBranchContracts);

        (uint256 balanceToRedeemAfter, uint256 userETotalCollateralValueAfter) = _redeemHalfOfUsersBalance(E);

        assertEq(
            balanceToRedeemBefore, balanceToRedeemAfter, "Adding branches should not affect user balance to redeem"
        );
        assertLe(
            userETotalCollateralValueBefore,
            userETotalCollateralValueAfter,
            "User E total collateral value should not decrease because of adding branches"
        );

        vm.deleteStateSnapshot(snapshot);
    }

    function testAuthorizationOnSetTroveCRs() public {
        uint256 troveIndex = 0;
        uint256 newCCR = 151e16;
        uint256 newMCR = 111e16;
        uint256 newSCR = 111e16;
        uint256 newBCR = 11e16;

        vm.startPrank(A);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, A));
        collateralRegistry.setTroveCCR(troveIndex, newCCR);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, A));
        collateralRegistry.setTroveMCR(troveIndex, newMCR);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, A));
        collateralRegistry.setTroveSCR(troveIndex, newSCR);
        vm.stopPrank();

        ITroveManager troveMng = collateralRegistry.getTroveManager(troveIndex);

        vm.startPrank(addrDeployer);

        vm.expectRevert(abi.encodeWithSelector(TroveManager.CallerNotCollateralRegistry.selector));
        troveMng.setNewBranchConfiguration(newSCR, newMCR, newCCR, newBCR, 5e16, 10e16, _1pct / 2 - 1);

        collateralRegistry.setTroveCCR(troveIndex, newCCR);
        collateralRegistry.setTroveMCR(troveIndex, newMCR);
        collateralRegistry.setTroveSCR(troveIndex, newSCR);

        vm.stopPrank();
    }

    function testSetCRValues() public {
        uint256 troveIndex = 0;
        uint256 newCCR = 151e16;
        uint256 newMCR = 111e16;
        uint256 newSCR = 111e16;

        vm.startPrank(addrDeployer);
        collateralRegistry.setTroveCCR(troveIndex, newCCR);
        collateralRegistry.setTroveMCR(troveIndex, newMCR);
        collateralRegistry.setTroveSCR(troveIndex, newSCR);
        vm.stopPrank();

        ITroveManager troveMng = collateralRegistry.getTroveManager(troveIndex);

        assertEq(troveMng.CCR(), newCCR);
        assertEq(troveMng.MCR(), newMCR);
        assertEq(troveMng.SCR(), newSCR);
    }

    function testConstraintsOnSetCRValues() public {
        uint256 troveIndex = 0;

        vm.startPrank(addrDeployer);

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveCCR(troveIndex, 100e16); // <= 100%

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveCCR(troveIndex, 200e16); // >= 200%

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveMCR(troveIndex, 100e16); // <= 100%

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveMCR(troveIndex, 200e16); // >= 200%

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveSCR(troveIndex, 100e16); // <= 100%

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveSCR(troveIndex, 200e16); // >= 200%

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveCCR(troveIndex, 110e16); // <= MCR

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveMCR(troveIndex, 151e16); // >= CCR

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveMCR(troveIndex, 109e16); // < SCR

        vm.expectRevert(abi.encodeWithSelector(TroveManager.InvalidParam.selector));
        collateralRegistry.setTroveSCR(troveIndex, 111e16); // > MCR

        vm.stopPrank();
    }

    function testEventsOnSetCRValues() public {
        uint256 troveIndex = 0;
        uint256 newCCR = 151e16;
        ITroveManager troveMng = collateralRegistry.getTroveManager(troveIndex);

        vm.startPrank(addrDeployer);
        vm.expectEmit();
        emit ITroveManager.BranchConfigurationUpdated(
            troveMng.SCR(),
            troveMng.MCR(),
            newCCR,
            troveMng.BCR(),
            troveMng.liquidationPenaltySP(),
            troveMng.liquidationPenaltyRedistribution(),
            troveMng.minAnnualInterestRate() 
        );
        collateralRegistry.setTroveCCR(troveIndex, newCCR);
        vm.stopPrank();
    }

    function testSetSPYield() public {
        vm.prank(addrDeployer);
        collateralRegistry.setSPYieldSplit(0, _100pct / 2);
    }

    function testSetNewInterestRouter() public {
        vm.prank(addrDeployer);
        collateralRegistry.setInterestRouter(0, address(1));
    }

    function testSetSPYieldInvalidCalls() public {
        // directly calling active pool
        vm.expectRevert("ActivePool: Caller is not CollateralRegistry");
        activePool.setSPYieldSplit(1);

        vm.startPrank(addrDeployer);
        // 0%
        vm.expectRevert(abi.encodeWithSelector(ActivePool.SPYieldSplitOutOfBounds.selector));
        collateralRegistry.setSPYieldSplit(0, 0);

        // > 100%
        vm.expectRevert(abi.encodeWithSelector(ActivePool.SPYieldSplitOutOfBounds.selector));
        collateralRegistry.setSPYieldSplit(0, _100pct + 1);

        vm.stopPrank();
    }

    function testSetNewInterestRouterInvalidCalls() public {
        // directly calling active pool

        vm.expectRevert("ActivePool: Caller is not CollateralRegistry");
        activePool.setInterestRouter(address(1));

        vm.startPrank(addrDeployer);
        // 0 address
        vm.expectRevert(abi.encodeWithSelector(ActivePool.ZeroAddressInterestRouter.selector));
        collateralRegistry.setInterestRouter(0, address(0));

        vm.stopPrank();
    }
}
