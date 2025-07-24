// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./DeployOrkiBase.sol";
// import "./InitialLiquidityHelpers.s.sol";

import "src/Interfaces/IInterestRouter.sol";
import "src/Quill/PriceFeeds/QuillSimplePriceFeed.sol";
import "src/Quill/PriceFeeds/QuillCompositePriceFeed.sol";
import {ICrocSwapDex} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapDex.sol";
import {setupAccessControl} from "script/SetupOrkiAccessControl.s.sol";
import {ICLFactory} from "src/Zappers/Modules/Exchanges/Slipstream/core/ICLFactory.sol";
import {ICrocSwapQuery} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapQuery.sol";
import {initCrocSwapPool, initCrocSwapETHPool} from "script/InitialLiquidityHelpers.s.sol";
import {ISlipstreamNonfungiblePositionManager} from "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamNonfungiblePositionManager.sol";
import {initSlipstreamLiquidityPool, InitSlipstreamLiquidityPoolArgs} from "script/VelodromeLiquidityPools.s.sol";

import { Multicall3 } from 'src/Quill/Multicall3.sol';

uint256 constant _24_HOURS = 86400;
uint256 constant _48_HOURS = 172800;

contract DeployOrkiSwellchain is DeployOrkiBase {
    bytes32 SALT;

    IWETH weth = IWETH(WETH_CA);
    IERC20Metadata weeth = IERC20Metadata(WEETH_CA);
    IERC20Metadata rsweth = IERC20Metadata(RSWETH_CA);
    IERC20Metadata ezeth = IERC20Metadata(EZETH_CA);
    IERC20Metadata rseth = IERC20Metadata(RSETH_CA);
    IERC20Metadata sweth = IERC20Metadata(SWETH_CA);
    // IERC20Metadata swbtc = IERC20Metadata(SWBTC_CA);
    IERC20Metadata swell = IERC20Metadata(SWELL_CA);
    IERC20Metadata usdc = IERC20Metadata(USDC_CA);

    address multicall;
    address eth_usd_oracle = 0xe7f71d6a24EBc391f5ee57B867ED429EB7Bd74f4;

    address weeth_eth_oracle = 0x3fd49f2146FE0e10c4AE7E3fE04b3d5126385Ac4;
    address rsweth_eth_oracle = 0x4BAD96DD1C7D541270a0C92e1D4e5f12EEEA7a57;
    address ezeth_eth_oracle = 0xbbF121624c3b85C929Ac83872bf6c86b0976A55e;
    address rseth_eth_oracle = 0x197225B3B017eb9b72Ac356D6B3c267d0c04c57c;
    address sweth_eth_oracle = 0x3587a73AA02519335A8a6053a97657BECe0bC2Cc;
    // address swbtc_eth_oracle = ; doesn't exist
    address swell_usd_oracle = 0x5C4c8d6f6Bf79B718F3e8399AaBdFEd01cB7e48f;

    uint256 generalThreshold = _24_HOURS;

    ICLFactory slipstreamPoolFactory = ICLFactory(0x04625B046C69577EfC40e6c0Bb83CDBAfab5a55F);
    ISlipstreamNonfungiblePositionManager slipstreamPositionManager =
        ISlipstreamNonfungiblePositionManager(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702);

    ICrocSwapDex crocSwapDex = ICrocSwapDex(0xaAAaAaaa82812F0a1f274016514ba2cA933bF24D);
    ICrocSwapQuery crocSwapQuery = ICrocSwapQuery(0xaab17419F062bB28CdBE82f9FC05E7C47C3F6194);

    // Initial liquidity values (these values need to be changed)
    uint256 constant USDC_PRECISION = 10 ** 6;

    uint256 constant initialLiquidityTroveUsdqAmount = 1000e18;
    uint256 constant initialLiquidityTroveWethAmount = 5e18;
    uint256 constant initialLiquidityTroveInterestRate = _1pct * 50;

    uint256 constant initialLiquiditySpAmount = 100e18;

    uint256 constant initialLiquidityUniV3USDQAmountUSDCPool = 1e18;
    uint256 constant initialLiquidityUniV3USDCAmountUSDCPool = 1e6;
    uint256 constant initialLiquidityUniV3USDQAmountWETHPool = 1e18;
    uint24 constant UNIV3_FEE = 0.3e4; // TODO: double check the UNIV3_FEE values for each liquidity pool
    uint24 constant UNIV3_FEE_STABLEPAIR = 0.05e4; // TODO: double check the UNIV3_FEE values for each liquidity pool

    address multisig = address(0x92B39Bfd1958869Fb2a03744591C6b3cF310D37C); // anvil#09
    address interestRouter = address(0x92B39Bfd1958869Fb2a03744591C6b3cF310D37C); // anvil#09
    // address multisig = address(0x32fD58B8c4D454aB585DEA736b7D2b5929B6676c);         //
    // address interestRouter = address(0x9c339BB827555AE214dF17b78c1aA28aCee183ce);

    address[] admins = new address[](0); // WARNING: deployer will be revoked from its ADMIN role
    address[] emergencyReponders = new address[](0);
    address[] accountsForHighTimelock = new address[](0);
    address[] accountsForMediumTimelock = new address[](0);
    address[] accountsForLowTimelock = new address[](0);

    struct DeploymentVars {
        uint256 numCollaterals;
        IAddressesRegistry[] addressesRegistries;
        ITroveManager[] troveManagers;
        Contracts contracts;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
        bytes bytecode;
        uint256 i;
        address quillAccessManagerAddress;
        address boldTokenAddress;
        address collateralRegistryAddress;
        address hintHelpersAddress;
        address multiTroveGetterAddress;
    }

    function run() external {
        SALT = bytes32(uint256(12012));
        upgradeOptions.customSalt = SALT;
        upgradeOptions.unsafeSkipAllChecks = true;

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

        if (block.chainid == 31337 || block.chainid == 7566690) {
            multicall = address(new Multicall3());
            console.log("MultiAddress", multicall);
        }

        admins.push(multisig);
        emergencyReponders.push(multisig);
        accountsForHighTimelock.push(multisig);
        accountsForMediumTimelock.push(multisig);
        accountsForLowTimelock.push(multisig);

        TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](5);

        // WETH
        troveManagerParamsArray[0] = TroveManagerParams({
            CCR: 140 * _1pct,
            MCR: 110 * _1pct,
            SCR: 110 * _1pct,
            BCR: 10 * _1pct,
            LIQUIDATION_PENALTY_SP: 5 * _1pct,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 5 * _1pct,
            MIN_DEBT: 500e18,
            SP_YIELD_SPLIT: 75 * _1pct,
            minAnnualInterestRate: 5 * _1pct,
            branchCap: WETH_BORROW_CAP
        });
        // rswETH
        troveManagerParamsArray[1] = TroveManagerParams({
            CCR: 160 * _1pct,
            MCR: 120 * _1pct,
            SCR: 120 * _1pct,
            BCR: 10 * _1pct,
            LIQUIDATION_PENALTY_SP: 5 * _1pct,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 75 * _1pct / 10, // 7.5%
            MIN_DEBT: 500e18,
            SP_YIELD_SPLIT: 75 * _1pct,
            minAnnualInterestRate: 5 * _1pct,
            branchCap: RSWETH_BORROW_CAP
        });
        // swETH
        troveManagerParamsArray[2] = TroveManagerParams({
            CCR: 150 * _1pct,
            MCR: 115 * _1pct,
            SCR: 115 * _1pct,
            BCR: 10 * _1pct,
            LIQUIDATION_PENALTY_SP: 5 * _1pct,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 75 * _1pct / 10, // 7.5%
            MIN_DEBT: 500e18,
            SP_YIELD_SPLIT: 75 * _1pct,
            minAnnualInterestRate: 5 * _1pct,
            branchCap: SWETH_BORROW_CAP
        });
        // SWELL
        troveManagerParamsArray[3] = TroveManagerParams({
            CCR: 170 * _1pct,
            MCR: 130 * _1pct,
            SCR: 130 * _1pct,
            BCR: 10 * _1pct,
            LIQUIDATION_PENALTY_SP: 5 * _1pct,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 10 * _1pct, // 10%
            MIN_DEBT: 500e18,
            SP_YIELD_SPLIT: 75 * _1pct,
            minAnnualInterestRate: 5 * _1pct,
            branchCap: SWELL_BORROW_CAP
        });
        // // weETH
        troveManagerParamsArray[4] = TroveManagerParams({
            CCR: 160 * _1pct,
            MCR: 120 * _1pct,
            SCR: 120 * _1pct,
            BCR: 10 * _1pct,
            LIQUIDATION_PENALTY_SP: 5 * _1pct,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 75 * _1pct / 10, // 7.5%
            MIN_DEBT: 500e18,
            SP_YIELD_SPLIT: 75 * _1pct,
            minAnnualInterestRate: 5 * _1pct,
            branchCap: WEETH_BORROW_CAP
        });
        // // ezETH
        // troveManagerParamsArray[5] = TroveManagerParams({
        //     CCR: 160 * _1pct,
        //     MCR: 120 * _1pct,
        //     SCR: 120 * _1pct,
            // BCR: 10 * _1pct,
        //     LIQUIDATION_PENALTY_SP: 5 * _1pct,
        //     LIQUIDATION_PENALTY_REDISTRIBUTION: 75 * _1pct / 10, // 7.5%
        //     MIN_DEBT: 500e18,
        //     SP_YIELD_SPLIT: 75 * _1pct,
        //     minAnnualInterestRate: 6 * _1pct,
        //     branchCap: EZETH_BORROW_CAP
        // });
        // // rsETH
        // troveManagerParamsArray[6] = TroveManagerParams({
        //     CCR: 160 * _1pct,
        //     MCR: 120 * _1pct,
        //     SCR: 120 * _1pct,
            // BCR: 10 * _1pct,
        //     LIQUIDATION_PENALTY_SP: 5 * _1pct,
        //     LIQUIDATION_PENALTY_REDISTRIBUTION: 75 * _1pct / 10, // 7.5%
        //     MIN_DEBT: 500e18,
        //     SP_YIELD_SPLIT: 75 * _1pct,
        //     minAnnualInterestRate: 6 * _1pct,
        //     branchCap: RSETH_BORROW_CAP
        // });

        DeploymentResult memory r;
        DeploymentVars memory vars;

        // Deploy QuillAccessManager
        r.quillAccessManager = QuillAccessManagerUpgradeable(
            Upgrades.deployUUPSProxy(
                "QuillAccessManagerUpgradeable.sol",
                abi.encodeCall(QuillAccessManagerUpgradeable.initialize, (deployer)),
                upgradeOptions
            )
        );
        vars.quillAccessManager = r.quillAccessManager;

        vars.quillAccessManagerAddress = computeUUPSProxyCreate2Address(
            type(QuillAccessManagerUpgradeable).creationCode,
            abi.encodeCall(QuillAccessManagerUpgradeable.initialize, (deployer)),
            upgradeOptions
        );

        assert(address(r.quillAccessManager) == vars.quillAccessManagerAddress);

        // used for gas compensation and as collateral of the first branch
        // IWETH WETH = IWETHnew WETHTester({_tapAmount: 100 ether, _tapPeriod: 1 days});

        Coll[] memory colls = new Coll[](5);
        colls[0] = Coll({
            token: IERC20Metadata(weth),
            priceFeed: new QuillSimplePriceFeed(address(r.quillAccessManager), eth_usd_oracle, generalThreshold)
        });

        colls[1] = Coll({
            token: rsweth,
            priceFeed: new QuillCompositePriceFeed(
                address(r.quillAccessManager), rsweth_eth_oracle, eth_usd_oracle, generalThreshold, generalThreshold
            )
        });

        colls[2] = Coll({
            token: sweth,
            priceFeed: new QuillCompositePriceFeed(
                address(r.quillAccessManager), sweth_eth_oracle, eth_usd_oracle, generalThreshold, generalThreshold
            )
        });

        colls[3] = Coll({
            token: swell,
            priceFeed: new QuillSimplePriceFeed(address(r.quillAccessManager), swell_usd_oracle, generalThreshold)
        });

        colls[4] = Coll({
            token: weeth,
            priceFeed: new QuillCompositePriceFeed(
                address(r.quillAccessManager), weeth_eth_oracle, eth_usd_oracle, generalThreshold, generalThreshold
            )
        });

        uint256[] memory mindebts = new uint256[](5);
        mindebts[0] = troveManagerParamsArray[0].MIN_DEBT;
        mindebts[1] = troveManagerParamsArray[1].MIN_DEBT;
        mindebts[2] = troveManagerParamsArray[2].MIN_DEBT;
        mindebts[3] = troveManagerParamsArray[3].MIN_DEBT;
        mindebts[4] = troveManagerParamsArray[4].MIN_DEBT;
        // mindebts[5] = troveManagerParamsArray[5].MIN_DEBT;
        // mindebts[6] = troveManagerParamsArray[6].MIN_DEBT;

        _enoughBalanceForDeploymentSafetyCheck(colls, mindebts);

        assert(colls.length == troveManagerParamsArray.length);

        vars.numCollaterals = troveManagerParamsArray.length;

        // Deploy SequencerSentinel
        r.sequencerSentinel = new QuillSequencerSentinel(
            address(vars.quillAccessManager),
            address(0),
            3600 // grace period 1h
        );

        vars.sequencerSentinel = r.sequencerSentinel;

        // Deploy Bold
        r.boldToken = BoldToken(
            Upgrades.deployUUPSProxy(
                "BoldToken.sol", abi.encodeCall(BoldToken.initialize, (address(r.quillAccessManager))), upgradeOptions
            )
        );

        vars.boldTokenAddress = computeUUPSProxyCreate2Address(
            type(BoldToken).creationCode,
            abi.encodeCall(BoldToken.initialize, (address(r.quillAccessManager))),
            upgradeOptions
        );

        assert(address(r.boldToken) == vars.boldTokenAddress);

        r.contractsArray = new Contracts[](vars.numCollaterals);
        vars.addressesRegistries = new IAddressesRegistry[](vars.numCollaterals);
        vars.troveManagers = new ITroveManager[](vars.numCollaterals);

        // Deploy AddressesRegistries and get TroveManager addresses
        for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
            (IAddressesRegistry addressesRegistry, address troveManagerAddress) =
                _deployAddressesRegistry(troveManagerParamsArray[vars.i], r.quillAccessManager);
            vars.addressesRegistries[vars.i] = addressesRegistry;
            vars.troveManagers[vars.i] = ITroveManager(troveManagerAddress);
        }

        IERC20Metadata[] memory _collaterals = new IERC20Metadata[](vars.numCollaterals);
        for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
            _collaterals[vars.i] = colls[vars.i].token;
        }

        r.collateralRegistry = CollateralRegistry(
            Upgrades.deployUUPSProxy(
                "CollateralRegistry.sol",
                abi.encodeCall(
                    CollateralRegistry.initialize, (address(r.quillAccessManager), r.boldToken, r.sequencerSentinel)
                ),
                upgradeOptions
            )
        );

        vars.collateralRegistryAddress = computeUUPSProxyCreate2Address(
            type(CollateralRegistry).creationCode,
            abi.encodeCall(
                CollateralRegistry.initialize, (address(r.quillAccessManager), r.boldToken, r.sequencerSentinel)
            ),
            upgradeOptions
        );

        assert(address(r.collateralRegistry) == vars.collateralRegistryAddress);

        r.boldToken.setCollateralRegistry(address(r.collateralRegistry));

        r.hintHelpers = HintHelpers(
            Upgrades.deployUUPSProxy(
                "HintHelpers.sol",
                abi.encodeCall(HintHelpers.initialize, (address(r.quillAccessManager), r.collateralRegistry)),
                upgradeOptions
            )
        );

        vars.hintHelpersAddress = computeUUPSProxyCreate2Address(
            type(HintHelpers).creationCode,
            abi.encodeCall(HintHelpers.initialize, (address(r.quillAccessManager), r.collateralRegistry)),
            upgradeOptions
        );

        assert(address(r.hintHelpers) == vars.hintHelpersAddress);

        r.multiTroveGetter = MultiTroveGetter(
            Upgrades.deployUUPSProxy(
                "MultiTroveGetter.sol",
                abi.encodeCall(MultiTroveGetter.initialize, (address(r.quillAccessManager), r.collateralRegistry)),
                upgradeOptions
            )
        );

        vars.multiTroveGetterAddress = computeUUPSProxyCreate2Address(
            type(MultiTroveGetter).creationCode,
            abi.encodeCall(MultiTroveGetter.initialize, (address(r.quillAccessManager), r.collateralRegistry)),
            upgradeOptions
        );

        assert(address(r.multiTroveGetter) == vars.multiTroveGetterAddress);

        // Deploy per-branch contracts for each branch
        for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
            vars.contracts = _deployAndConnectCollateralContracts(
                colls[vars.i].token,
                r.boldToken,
                r.collateralRegistry,
                weth,
                vars.addressesRegistries[vars.i],
                address(vars.troveManagers[vars.i]),
                r.hintHelpers,
                r.multiTroveGetter,
                r.sequencerSentinel,
                troveManagerParamsArray[vars.i],
                colls[vars.i].priceFeed
            );
            r.contractsArray[vars.i] = vars.contracts;
        }

        _createZombieTrovesAsDeployer_OpeningTroves(r);

        r.contractsArray[0].collToken.approve(
            address(r.contractsArray[0].borrowerOperations),
            initialLiquidityTroveWethAmount + 5e15 //5e15 gas compensation
        );

        _depositInStabilityPools(r);

        vm.stopBroadcast();
        vm.writeFile("deployment-manifest.json", _getManifestJson(r));
    }

    function _deployAddressesRegistry(
        TroveManagerParams memory _troveManagerParams,
        QuillAccessManagerUpgradeable quillAccessManager
    ) internal returns (IAddressesRegistry, address) {
        IAddressesRegistry addressesRegistry = new AddressesRegistry(
            address(quillAccessManager),
            _troveManagerParams.LIQUIDATION_PENALTY_SP,
            _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        address troveManagerAddress = vm.computeCreate2Address(
            SALT,
            keccak256(getBytecode(type(TroveManager).creationCode, address(addressesRegistry), _troveManagerParams))
        );

        return (addressesRegistry, troveManagerAddress);
    }

    function _deployAndConnectCollateralContracts(
        IERC20Metadata _collToken,
        IBoldToken _boldToken,
        ICollateralRegistry _collateralRegistry,
        IWETH _weth,
        IAddressesRegistry _addressesRegistry,
        address _troveManagerAddress,
        IHintHelpers _hintHelpers,
        IMultiTroveGetter _multiTroveGetter,
        ISequencerSentinel _sequencerSentinel,
        TroveManagerParams memory _troveManagerParams,
        IPriceFeed _priceFeed
    ) internal returns (Contracts memory contracts) {
        Branch memory addresses;
        contracts.collToken = _collToken;

        // Deploy all contracts, using testers for TM and PriceFeed
        contracts.addressesRegistry = _addressesRegistry;

        // Deploy Metadata
        contracts.metadataNFT = deployMetadata(SALT, _collToken.symbol());
        addresses.metadataNFT = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(MetadataNFT).creationCode, address(initializedFixedAssetReader)))
        );
        assert(address(contracts.metadataNFT) == addresses.metadataNFT);

        contracts.priceFeed = _priceFeed;
        contracts.interestRouter = IInterestRouter(interestRouter);
        addresses.borrowerOperations = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(BorrowerOperations).creationCode, address(contracts.addressesRegistry)))
        );
        addresses.troveManager = _troveManagerAddress;
        addresses.troveNFT = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(TroveNFT).creationCode, address(contracts.addressesRegistry)))
        );
        addresses.stabilityPool = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(StabilityPool).creationCode, address(contracts.addressesRegistry)))
        );
        addresses.activePool = vm.computeCreate2Address(
            SALT,
            keccak256(
                getBytecode(
                    type(ActivePool).creationCode,
                    address(contracts.addressesRegistry),
                    _troveManagerParams.SP_YIELD_SPLIT
                )
            )
        );
        addresses.defaultPool = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(DefaultPool).creationCode, address(contracts.addressesRegistry)))
        );
        addresses.gasPool = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(GasPool).creationCode, address(contracts.addressesRegistry)))
        );
        addresses.collSurplusPool = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(CollSurplusPool).creationCode, address(contracts.addressesRegistry)))
        );
        addresses.sortedTroves = vm.computeCreate2Address(
            SALT, keccak256(getBytecode(type(SortedTroves).creationCode, address(contracts.addressesRegistry)))
        );

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
            hintHelpers: _hintHelpers,
            multiTroveGetter: _multiTroveGetter,
            collateralRegistry: _collateralRegistry,
            boldToken: _boldToken,
            sequencerSentinel: _sequencerSentinel,
            WETH: _weth
        });
        contracts.addressesRegistry.setAddresses(addressVars);
        contracts.priceFeed.setAddresses(addresses.borrowerOperations);

        contracts.borrowerOperations = new BorrowerOperations{salt: SALT}(contracts.addressesRegistry);
        contracts.troveManager = new TroveManager{salt: SALT}(
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
        contracts.defaultPool = new DefaultPool{salt: SALT}(contracts.addressesRegistry);
        contracts.gasPool = new GasPool{salt: SALT}(contracts.addressesRegistry);
        contracts.collSurplusPool = new CollSurplusPool{salt: SALT}(contracts.addressesRegistry);
        contracts.sortedTroves = new SortedTroves{salt: SALT}(contracts.addressesRegistry);

        assert(address(contracts.borrowerOperations) == addresses.borrowerOperations);
        assert(address(contracts.troveManager) == addresses.troveManager);
        assert(address(contracts.troveNFT) == addresses.troveNFT);
        assert(address(contracts.stabilityPool) == addresses.stabilityPool);
        assert(address(contracts.activePool) == addresses.activePool);
        assert(address(contracts.defaultPool) == addresses.defaultPool);
        assert(address(contracts.gasPool) == addresses.gasPool);
        assert(address(contracts.collSurplusPool) == addresses.collSurplusPool);
        assert(address(contracts.sortedTroves) == addresses.sortedTroves);

        // Connect contracts
        _collateralRegistry.addCollateral(_collToken, contracts.troveManager, _troveManagerParams.branchCap);

        // deploy zappers
        (contracts.gasCompZapper, contracts.wethZapper, contracts.leverageZapper) =
            _deployZappers(contracts.addressesRegistry, contracts.collToken, _weth);
    }

    function _deployZappers(IAddressesRegistry _addressesRegistry, IERC20 _collToken, IWETH _weth)
        internal
        returns (GasCompZapper gasCompZapper, WETHZapper wethZapper, ILeverageZapper leverageZapper)
    {
        // TODO: currently skippping flash loan and exchange provider
        // until we figure out which ones to use on scroll
        // I set this to address(1) to avoid reverting on deployment
        // Issue URL: https://github.com/subvisual/quill/issues/114
        IFlashLoanProvider flashLoanProvider = IFlashLoanProvider(address(0));
        IExchange exchange = IExchange(address(0));

        if (_collToken != _weth) {
            gasCompZapper = new GasCompZapper(_addressesRegistry, flashLoanProvider, exchange);
            leverageZapper = new LeverageLSTZapper(_addressesRegistry, flashLoanProvider, exchange);
        } else {
            wethZapper = new WETHZapper(_addressesRegistry, flashLoanProvider, exchange);
            leverageZapper = new LeverageWETHZapper(_addressesRegistry, flashLoanProvider, exchange);
        }
    }
}
