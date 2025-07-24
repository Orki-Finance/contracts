// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./DeployQuillBase.sol";

contract DeployQuillLocal is DeployQuillBase {
    bytes32 SALT;

    struct DeploymentVars {
        uint256 numCollaterals;
        ERC20Faucet[] collaterals;
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

    function run() external virtual {
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

        TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](4);
        troveManagerParamsArray[0] =
            TroveManagerParams(150e16, 110e16, 110e16, 10e16, 5e16, 10e16, 500e18, 72e16, _1pct / 2, WETH_BORROW_CAP); // WETH
        troveManagerParamsArray[1] =
            TroveManagerParams(150e16, 120e16, 110e16, 10e16, 5e16, 10e16, 500e18, 72e16, _1pct / 2, WSTETH_BORROW_CAP); // wstETH
        troveManagerParamsArray[2] =
            TroveManagerParams(150e16, 120e16, 110e16, 10e16, 5e16, 10e16, 500e18, 72e16, _1pct / 2, WEETH_BORROW_CAP); // weETH
        troveManagerParamsArray[3] =
            TroveManagerParams(150e16, 120e16, 110e16, 10e16, 5e16, 10e16, 500e18, 72e16, _1pct / 2, SCROLL_BORROW_CAP); // SCROLL

        // used for gas compensation and as collateral of the first branch
        WETHTester WETH = new WETHTester({_tapAmount: 100 ether, _tapPeriod: 0});

        string[] memory collNames = new string[](3);
        string[] memory collSymbols = new string[](3);
        collNames[0] = "Wrapped liquid staked Ether 2.0";
        collSymbols[0] = "wstETH";
        collNames[1] = "Wrapper ether.fi ETH";
        collSymbols[1] = "weETH";
        collNames[2] = "Scroll";
        collSymbols[2] = "SCR";

        DeploymentResult memory deployed =
            _deployAndConnectContracts(troveManagerParamsArray, WETH, collNames, collSymbols);

        vm.stopBroadcast();

        vm.writeFile("deployment-manifest.json", _getManifestJson(deployed));

        for (uint256 i = 0; i < deployed.contractsArray.length; i++) {
            tapDeployer(deployed.contractsArray[i]);
        }

        vm.startBroadcast(deployer);
        _createZombieTrovesAsDeployer_OpeningTroves(deployed);
        _createZombieTrovesAsDeployer_RedeemingUSDq(deployed);
        vm.stopBroadcast();

        if (vm.envOr("OPEN_DEMO_TROVES", false)) {
            console.log("her");
            // Anvil default accounts
            uint256[] memory demoAccounts = new uint256[](8);
            demoAccounts[0] = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            demoAccounts[1] = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
            demoAccounts[2] = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
            demoAccounts[3] = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
            demoAccounts[4] = 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a;
            demoAccounts[5] = 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba;
            demoAccounts[6] = 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e;
            demoAccounts[7] = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

            DemoTroveParams[] memory demoTroves = new DemoTroveParams[](16);

            demoTroves[0] = DemoTroveParams(0, demoAccounts[0], 1, 25e18, 2800e18, 5.0e16);
            demoTroves[1] = DemoTroveParams(0, demoAccounts[1], 0, 37e18, 2400e18, 4.7e16);
            demoTroves[2] = DemoTroveParams(0, demoAccounts[2], 0, 30e18, 4000e18, 3.3e16);
            demoTroves[3] = DemoTroveParams(0, demoAccounts[3], 0, 65e18, 6000e18, 4.3e16);

            demoTroves[4] = DemoTroveParams(0, demoAccounts[4], 0, 19e18, 2280e18, 5.0e16);
            demoTroves[5] = DemoTroveParams(0, demoAccounts[5], 0, 48.37e18, 4400e18, 4.7e16);
            demoTroves[6] = DemoTroveParams(0, demoAccounts[6], 0, 33.92e18, 5500e18, 3.8e16);
            demoTroves[7] = DemoTroveParams(0, demoAccounts[7], 0, 47.2e18, 6000e18, 4.3e16);

            demoTroves[8] = DemoTroveParams(1, demoAccounts[0], 1, 21e18, 2000e18, 3.3e16);
            demoTroves[9] = DemoTroveParams(1, demoAccounts[1], 0, 16e18, 2000e18, 4.1e16);
            demoTroves[10] = DemoTroveParams(1, demoAccounts[2], 0, 18e18, 2300e18, 3.8e16);
            demoTroves[11] = DemoTroveParams(1, demoAccounts[3], 0, 22e18, 2200e18, 4.3e16);

            demoTroves[12] = DemoTroveParams(1, demoAccounts[4], 0, 85e18, 12000e18, 7.0e16);
            demoTroves[13] = DemoTroveParams(1, demoAccounts[5], 0, 87e18, 4000e18, 4.4e16);
            demoTroves[14] = DemoTroveParams(1, demoAccounts[6], 0, 71e18, 11000e18, 3.3e16);
            demoTroves[15] = DemoTroveParams(1, demoAccounts[7], 0, 84e18, 12800e18, 4.4e16);

            for (uint256 i = 0; i < deployed.contractsArray.length; i++) {
                tapFaucet(demoAccounts, deployed.contractsArray[i]);
            }

            openDemoTroves(demoTroves, deployed.contractsArray);
        }
    }

    function tapDeployer(Contracts memory contracts) internal {
        ERC20Faucet token = ERC20Faucet(address(contracts.collToken));

        vm.startBroadcast(deployer);
        token.tap();
        vm.stopBroadcast();
    }

    function tapFaucet(uint256[] memory accounts, Contracts memory contracts) internal {
        for (uint256 i = 0; i < accounts.length; i++) {
            ERC20Faucet token = ERC20Faucet(address(contracts.collToken));

            vm.startBroadcast(accounts[i]);
            token.tap();
            vm.stopBroadcast();

            console.log(
                "%s.tap() => %s (balance: %s)",
                token.symbol(),
                vm.addr(accounts[i]),
                string.concat(formatAmount(token.balanceOf(vm.addr(accounts[i])), 18, 2), " ", token.symbol())
            );
        }
    }

    function openDemoTroves(DemoTroveParams[] memory demoTroves, Contracts[] memory contractsArray) internal {
        for (uint256 i = 0; i < demoTroves.length; i++) {
            DemoTroveParams memory trove = demoTroves[i];
            Contracts memory contracts = contractsArray[trove.collIndex];

            vm.startBroadcast(trove.owner);

            IERC20 collToken = IERC20(contracts.collToken);
            IERC20 wethToken = IERC20(contracts.addressesRegistry.WETH());

            // Approve collToken to BorrowerOperations
            if (collToken == wethToken) {
                wethToken.approve(address(contracts.borrowerOperations), trove.coll + ETH_GAS_COMPENSATION);
            } else {
                wethToken.approve(address(contracts.borrowerOperations), ETH_GAS_COMPENSATION);
                collToken.approve(address(contracts.borrowerOperations), trove.coll);
            }

            IBorrowerOperations(contracts.borrowerOperations).openTrove(
                vm.addr(trove.owner), //     _owner
                trove.ownerIndex, //         _ownerIndex
                trove.coll, //               _collAmount
                trove.debt, //               _boldAmount
                0, //                        _upperHint
                0, //                        _lowerHint
                trove.annualInterestRate, // _annualInterestRate
                type(uint256).max, //        _maxUpfrontFee
                address(0), //               _addManager
                address(0), //               _removeManager
                address(0) //                _receiver
            );

            vm.stopBroadcast();
        }
    }

    function _deployAndConnectContracts(
        TroveManagerParams[] memory troveManagerParamsArray,
        WETHTester _WETH,
        string[] memory _collNames,
        string[] memory _collSymbols
    ) internal returns (DeploymentResult memory r) {
        assert(_collNames.length == troveManagerParamsArray.length - 1);
        assert(_collSymbols.length == troveManagerParamsArray.length - 1);

        DeploymentVars memory vars;
        vars.numCollaterals = troveManagerParamsArray.length;

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
        // Deploy SequencerSentinel
        r.sequencerSentinel = new QuillSequencerSentinelMainnet();
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
        vars.collaterals = new ERC20Faucet[](vars.numCollaterals);
        vars.addressesRegistries = new IAddressesRegistry[](vars.numCollaterals);
        vars.troveManagers = new ITroveManager[](vars.numCollaterals);

        // Use WETH as collateral for the first branch
        vars.collaterals[0] = _WETH;

        // Deploy plain ERC20Faucets for the rest of the branches
        for (vars.i = 1; vars.i < vars.numCollaterals; vars.i++) {
            vars.collaterals[vars.i] = new ERC20Faucet(
                _collNames[vars.i - 1], //   _name
                _collSymbols[vars.i - 1], // _symbol
                100 ether, //     _tapAmount
                0 //         _tapPeriod
            );
        }

        // Deploy AddressesRegistries and get TroveManager addresses
        for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
            (IAddressesRegistry addressesRegistry, address troveManagerAddress) =
                _deployAddressesRegistry(troveManagerParamsArray[vars.i], r.quillAccessManager);
            vars.addressesRegistries[vars.i] = addressesRegistry;
            vars.troveManagers[vars.i] = ITroveManager(troveManagerAddress);
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
                vars.collaterals[vars.i],
                r.boldToken,
                r.collateralRegistry,
                _WETH,
                vars.addressesRegistries[vars.i],
                address(vars.troveManagers[vars.i]),
                r.hintHelpers,
                r.multiTroveGetter,
                r.sequencerSentinel,
                troveManagerParamsArray[vars.i]
            );
            r.contractsArray[vars.i] = vars.contracts;
        }
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
        ERC20Faucet _collToken,
        IBoldToken _boldToken,
        ICollateralRegistry _collateralRegistry,
        IWETH _weth,
        IAddressesRegistry _addressesRegistry,
        address _troveManagerAddress,
        IHintHelpers _hintHelpers,
        IMultiTroveGetter _multiTroveGetter,
        ISequencerSentinel _sequencerSentinel,
        TroveManagerParams memory _troveManagerParams
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

        contracts.priceFeed = new PriceFeedTestnet();
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
