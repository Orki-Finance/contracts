// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./DeployOrkiBase.sol";

uint256 constant _24_HOURS = 86400;
uint256 constant _48_HOURS = 172800;

contract DeployOrkiSwellchainTestnet is DeployOrkiBase {
    bytes32 SALT;

    WETHTester weth;
    ERC20Faucet rsweth;
    ERC20Faucet sweth;
    ERC20Faucet swell;
    ERC20Faucet swbtc;

    PriceFeedTestnet ethPriceFeed;
    PriceFeedTestnet rswethPriceFeed;
    PriceFeedTestnet swethPriceFeed;
    PriceFeedTestnet swellPriceFeed;
    PriceFeedTestnet swbtcPriceFeed;

    struct DeploymentVars {
        uint256 numCollaterals;
        IAddressesRegistry[] addressesRegistries;
        ITroveManager[] troveManagers;
        Contracts contracts;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
        bytes bytecode;
        address boldTokenAddress;
        uint256 i;
    }

    function run() external {
        SALT = keccak256(abi.encodePacked(block.timestamp));
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

        _deployMockCollaterals();

        TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](4);
        troveManagerParamsArray[0] =
            TroveManagerParams(140e16, 110e16, 110e16, 10e16, 5e16, 10e16, 500e18, 75e16, 6 * _1pct, WETH_BORROW_CAP); // WETH
        troveManagerParamsArray[1] =
            TroveManagerParams(160e16, 120e16, 120e16, 10e16, 5e16, 10e16, 500e18, 75e16, 6 * _1pct, RSWETH_BORROW_CAP); // rsweth
        troveManagerParamsArray[2] =
            TroveManagerParams(160e16, 120e16, 120e16, 10e16, 5e16, 10e16, 500e18, 75e16, 6 * _1pct, SWETH_BORROW_CAP); // sweth
        troveManagerParamsArray[3] =
            TroveManagerParams(160e16, 120e16, 120e16, 10e16, 5e16, 10e16, 500e18, 75e16, 7 * _1pct, SWELL_BORROW_CAP); // SWELL

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

        // used for gas compensation and as collateral of the first branch
        // IWETH WETH = IWETHnew WETHTester({_tapAmount: 100 ether, _tapPeriod: 1 days});

        Coll[] memory colls = new Coll[](4);
        colls[0] = Coll({token: IERC20Metadata(weth), priceFeed: ethPriceFeed});
        colls[1] = Coll({token: rsweth, priceFeed: rswethPriceFeed});
        colls[2] = Coll({token: sweth, priceFeed: swethPriceFeed});
        colls[3] = Coll({token: swell, priceFeed: swellPriceFeed});

        assert(colls.length == troveManagerParamsArray.length);
        vars.numCollaterals = troveManagerParamsArray.length;

        // Deploy SequencerSentinel
        r.sequencerSentinel = new QuillSequencerSentinelMainnet();
        vars.sequencerSentinel = r.sequencerSentinel;
        // Deploy Bold
        r.boldToken = BoldToken(
            Upgrades.deployUUPSProxy(
                "BoldToken.sol", abi.encodeCall(BoldToken.initialize, (address(r.quillAccessManager))), upgradeOptions
            )
        );
        vars.boldTokenAddress = address(r.boldToken);
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
        r.boldToken.setCollateralRegistry(address(r.collateralRegistry));
        r.hintHelpers = HintHelpers(
            Upgrades.deployUUPSProxy(
                "HintHelpers.sol",
                abi.encodeCall(HintHelpers.initialize, (address(r.quillAccessManager), r.collateralRegistry)),
                upgradeOptions
            )
        );

        r.multiTroveGetter = MultiTroveGetter(
            Upgrades.deployUUPSProxy(
                "MultiTroveGetter.sol",
                abi.encodeCall(MultiTroveGetter.initialize, (address(r.quillAccessManager), r.collateralRegistry)),
                upgradeOptions
            )
        );

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
        _createZombieTrovesAsDeployer_RedeemingUSDq(r);

        vm.stopBroadcast();
        vm.writeFile("deployment-manifest.json", _getManifestJson(r));
    }

    function _deployMockCollaterals() internal {
        // tapping disallowed for WETH
        weth = new WETHTester({_tapAmount: 0, _tapPeriod: type(uint256).max});
        weth.deposit{value: 100 ether}();
        rsweth = new ERC20Faucet("rswETH", "rswETH", 100 ether, 1 days);
        rsweth.tap();
        sweth = new ERC20Faucet("swETH", "swETH", 100 ether, 1 days);
        sweth.tap();
        swell = new ERC20Faucet("Swell Governance Token", "SWELL", 100_000 ether, 1 days);
        swell.tap();

        ethPriceFeed = new PriceFeedTestnet();
        rswethPriceFeed = new PriceFeedTestnet();
        swethPriceFeed = new PriceFeedTestnet();
        swellPriceFeed = new PriceFeedTestnet();
        swbtcPriceFeed = new PriceFeedTestnet();

        ethPriceFeed.setPrice(200 * 1e18);
        rswethPriceFeed.setPrice(220 * 1e18);
        swethPriceFeed.setPrice(210 * 1e18);
        swellPriceFeed.setPrice(0.3 * 1e18);
        swbtcPriceFeed.setPrice(1000 * 1e18);
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
        contracts.interestRouter = new MockInterestRouter();
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
        // until we figure out which ones to use on swell
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
