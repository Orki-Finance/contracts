// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "src/AddressesRegistry.sol";
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
import "./BorrowerOperationsTester.t.sol";
import "./TroveManagerTester.t.sol";
import "./CollateralRegistryTester.sol";
import "src/TroveNFT.sol";
import "src/NFTMetadata/MetadataNFT.sol";
import "src/CollateralRegistry.sol";
import "./MockInterestRouter.sol";
import "./PriceFeedTestnet.sol";
import "../../script/MetadataDeployment.sol";
import "src/Zappers/WETHZapper.sol";
import "src/Zappers/GasCompZapper.sol";
import "src/Zappers/LeverageLSTZapper.sol";
import "src/Zappers/LeverageWETHZapper.sol";
import "src/Zappers/Modules/FlashLoans/BalancerFlashLoan.sol";
import "src/Zappers/Interfaces/IFlashLoanProvider.sol";
import "src/Zappers/Interfaces/IExchange.sol";
import "src/Zappers/Modules/Exchanges/Curve/ICurveFactory.sol";
import "src/Zappers/Modules/Exchanges/Curve/ICurveStableswapNGFactory.sol";
import "src/Zappers/Modules/Exchanges/Curve/ICurvePool.sol";
import "src/Zappers/Modules/Exchanges/Curve/ICurveStableswapNGPool.sol";
import "src/Zappers/Modules/Exchanges/CurveExchange.sol";
import "src/Zappers/Modules/Exchanges/UniswapV3/ISwapRouter.sol";
import "src/Zappers/Modules/Exchanges/UniV3Exchange.sol";
import "src/Zappers/Modules/Exchanges/UniswapV3/INonfungiblePositionManager.sol";
import "src/Zappers/Modules/Exchanges/HybridCurveUniV3Exchange.sol";
import {WETHTester} from "./WETHTester.sol";
import {ERC20Faucet} from "./ERC20Faucet.sol";

import "src/PriceFeeds/WETHPriceFeed.sol";
import "src/PriceFeeds/WSTETHPriceFeed.sol";
import "src/PriceFeeds/RETHPriceFeed.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {QuillAccessManagerUpgradeable} from "../../src/Quill/QuillAccessManagerUpgradeable.sol";
import {QuillSequencerSentinelMainnet} from "../../src/Quill/SequencerSentinel/Mainnet.sol";

uint256 constant _24_HOURS = 86400;
uint256 constant _48_HOURS = 172800;

// TODO: Split dev and mainnet
contract TestDeployer is MetadataDeployment {
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH constant WETH_MAINNET = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Curve
    ICurveFactory constant curveFactory = ICurveFactory(0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F);
    ICurveStableswapNGFactory constant curveStableswapFactory =
        ICurveStableswapNGFactory(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf);
    uint128 constant BOLD_TOKEN_INDEX = 0;
    uint256 constant COLL_TOKEN_INDEX = 1;
    uint128 constant USDC_INDEX = 1;

    // UniV3
    ISwapRouter constant uniV3Router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager constant uniV3PositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    uint24 constant UNIV3_FEE = 3000; // 0.3%
    uint24 constant UNIV3_FEE_USDC_WETH = 500; // 0.05%
    uint24 constant UNIV3_FEE_WETH_COLL = 100; // 0.01%

    bytes32 constant SALT = keccak256("Quill Protocol");

    struct LiquityContractsDevPools {
        IDefaultPool defaultPool;
        ICollSurplusPool collSurplusPool;
        GasPool gasPool;
    }

    struct LiquityContractsDev {
        IAddressesRegistry addressesRegistry;
        IBorrowerOperationsTester borrowerOperations; // Tester
        ISortedTroves sortedTroves;
        IActivePool activePool;
        IStabilityPool stabilityPool;
        ITroveManagerTester troveManager; // Tester
        ITroveNFT troveNFT;
        IPriceFeedTestnet priceFeed; // Tester
        IInterestRouter interestRouter;
        IERC20Metadata collToken;
        LiquityContractsDevPools pools;
    }

    struct LiquityContracts {
        IAddressesRegistry addressesRegistry;
        IActivePool activePool;
        IBorrowerOperations borrowerOperations;
        ICollSurplusPool collSurplusPool;
        IDefaultPool defaultPool;
        ISortedTroves sortedTroves;
        IStabilityPool stabilityPool;
        ITroveManager troveManager;
        ITroveNFT troveNFT;
        IPriceFeed priceFeed;
        GasPool gasPool;
        IInterestRouter interestRouter;
        IERC20Metadata collToken;
    }

    struct Zappers {
        WETHZapper wethZapper;
        GasCompZapper gasCompZapper;
        ILeverageZapper leverageZapperCurve;
        ILeverageZapper leverageZapperUniV3;
        ILeverageZapper leverageZapperHybrid;
    }

    struct LiquityContractAddresses {
        address activePool;
        address borrowerOperations;
        address collSurplusPool;
        address defaultPool;
        address sortedTroves;
        address stabilityPool;
        address troveManager;
        address troveNFT;
        address metadataNFT;
        address priceFeed;
        address gasPool;
        address interestRouter;
    }

    struct TroveManagerParams {
        uint256 CCR;
        uint256 MCR;
        uint256 SCR;
        uint256 BCR;
        uint256 LIQUIDATION_PENALTY_SP;
        uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
        uint256 MIN_DEBT;
        uint256 SP_YIELD_SPLIT;
        uint256 minAnnualInterestRate;
    }

    struct DeploymentVarsDev {
        uint256 numCollaterals;
        IERC20Metadata[] collaterals;
        IAddressesRegistry[] addressesRegistries;
        ITroveManager[] troveManagers;
        bytes bytecode;
        address boldTokenAddress;
        uint256 i;
    }

    struct DeploymentResultMainnet {
        LiquityContracts[] contractsArray;
        ExternalAddresses externalAddresses;
        CollateralRegistryTester collateralRegistry;
        IBoldToken boldToken;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        Zappers[] zappersArray;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
    }

    struct DeploymentVarsMainnet {
        OracleParams oracleParams;
        uint256 numCollaterals;
        IERC20Metadata[] collaterals;
        IAddressesRegistry[] addressesRegistries;
        ITroveManager[] troveManagers;
        IPriceFeed[] priceFeeds;
        ISequencerSentinel sequencerSentinel;
        QuillAccessManagerUpgradeable quillAccessManager;
        bytes bytecode;
        address boldTokenAddress;
        uint256 i;
    }

    struct DeploymentParamsDev {
        IERC20Metadata collToken;
        IBoldToken boldToken;
        ICollateralRegistry collateralRegistry;
        IWETH weth;
        IAddressesRegistry addressesRegistry;
        address troveManagerAddress;
        IHintHelpers hintHelpers;
        IMultiTroveGetter multiTroveGetter;
        ISequencerSentinel sequencerSentinel;
        TroveManagerParams troveManagerParams;
    }

    struct DeploymentParamsMainnet {
        IERC20Metadata collToken;
        IPriceFeed priceFeed;
        IBoldToken boldToken;
        ICollateralRegistry collateralRegistry;
        IWETH weth;
        IAddressesRegistry addressesRegistry;
        address troveManagerAddress;
        IHintHelpers hintHelpers;
        IMultiTroveGetter multiTroveGetter;
        ICurveStableswapNGPool usdcCurvePool;
        ISequencerSentinel sequencerSentinel;
        TroveManagerParams troveManagerParams;
    }

    struct ExternalAddresses {
        address ETHOracle;
        address STETHOracle;
        address RETHOracle;
        address WSTETHToken;
        address RETHToken;
    }

    struct OracleParams {
        uint256 ethUsdStalenessThreshold;
        uint256 stEthUsdStalenessThreshold;
        uint256 rEthEthStalenessThreshold;
        uint256 ethXEthStalenessThreshold;
        uint256 osEthEthStalenessThreshold;
    }

    // See: https://solidity-by-example.org/app/create2/
    function getBytecode(bytes memory _creationCode, address _addressesRegistry) public pure returns (bytes memory) {
        return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry));
    }

    function getBytecode(
        bytes memory _creationCode,
        address _addressesRegistry,
        TroveManagerParams memory _troveManagerParams
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            _creationCode,
            abi.encode(
                _addressesRegistry,
                _troveManagerParams.CCR,
                _troveManagerParams.MCR,
                _troveManagerParams.SCR,
                _troveManagerParams.BCR,
                _troveManagerParams.MIN_DEBT,
                _troveManagerParams.minAnnualInterestRate,
                _troveManagerParams.LIQUIDATION_PENALTY_SP,
                _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
            )
        );
    }

    function getBytecode(bytes memory _creationCode, address _addressesRegistry, uint256 newVar)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry, newVar));
    }

    function getAddress(address _deployer, bytes memory _bytecode, bytes32 _salt) public pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), _deployer, _salt, keccak256(_bytecode)));

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    struct DeployedContracts {
        LiquityContractsDev contracts;
        ICollateralRegistry collateralRegistry;
        IBoldToken boldToken;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        IWETH WETH; // for gas compensation
        Zappers zappers;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
    }

    struct DeployedContractsMultiColl {
        LiquityContractsDev[] contractsArray;
        ICollateralRegistry collateralRegistry;
        IBoldToken boldToken;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        IWETH WETH; // for gas compensation
        Zappers[] zappersArray;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
    }

    function deployAndConnectContracts() external returns (DeployedContracts memory) {
        return deployAndConnectContracts(
            TroveManagerParams(150e16, 110e16, 110e16, 10e16, 5e16, 10e16, 2000e18, 72e16, _1pct / 2)
        );
    }

    function deployAndConnectContracts(TroveManagerParams memory troveManagerParams)
        public
        returns (DeployedContracts memory res)
    {
        TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](1);

        troveManagerParamsArray[0] = troveManagerParams;

        DeployedContractsMultiColl memory multiColRes = deployAndConnectContractsMultiColl(troveManagerParamsArray);

        res.contracts = multiColRes.contractsArray[0];
        res.collateralRegistry = multiColRes.collateralRegistry;
        res.boldToken = multiColRes.boldToken;
        res.hintHelpers = multiColRes.hintHelpers;
        res.multiTroveGetter = multiColRes.multiTroveGetter;
        res.WETH = multiColRes.WETH; // for gas compensation
        res.zappers = multiColRes.zappersArray[0];
        res.quillAccessManager = multiColRes.quillAccessManager;
        res.sequencerSentinel = multiColRes.sequencerSentinel;
    }

    function deployAndConnectContractsMultiColl(TroveManagerParams[] memory troveManagerParamsArray)
        public
        returns (DeployedContractsMultiColl memory res)
    {
        // used for gas compensation and as collateral of the first branch
        res.WETH = new WETHTester(
            100 ether, //     _tapAmount
            1 days //         _tapPeriod
        );

        return deployAndConnectContracts(troveManagerParamsArray, res.WETH);
    }

    function _nameToken(uint256 _index) internal pure virtual returns (string memory) {
        if (_index == 1) return "Wrapped Staked Ether";
        if (_index == 2) return "Rocket Pool ETH";
        return "LST Tester";
    }

    function _symboltoken(uint256 _index) internal pure virtual returns (string memory) {
        if (_index == 1) return "wstETH";
        if (_index == 2) return "rETH";
        return "LST";
    }

    /// @dev deployAndConnectContracts was running into stack too deep errors when adding additional state
    struct TmpDeployAndConnectContracts {
        LiquityContractsDev[] contractsArray;
        ICollateralRegistry collateralRegistry;
        IBoldToken boldToken;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        Zappers[] zappersArray;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
        DeploymentVarsDev vars;
    }

    function deployAndConnectContracts(TroveManagerParams[] memory troveManagerParamsArray, IWETH _WETH)
        public
        returns (DeployedContractsMultiColl memory res)
    {
        TmpDeployAndConnectContracts memory t;
        t.vars.numCollaterals = troveManagerParamsArray.length;

        t.quillAccessManager = QuillAccessManagerUpgradeable(
            UnsafeUpgrades.deployUUPSProxy(
                address(new QuillAccessManagerUpgradeable()),
                abi.encodeCall(QuillAccessManagerUpgradeable.initialize, (address(this)))
            )
        );

        // Deploy Bold
        t.boldToken = BoldToken(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BoldToken()), abi.encodeCall(BoldToken.initialize, (address(t.quillAccessManager)))
            )
        );
        console.log(address(t.boldToken));
        t.vars.boldTokenAddress = address(t.boldToken);
        t.sequencerSentinel = new QuillSequencerSentinelMainnet();

        t.contractsArray = new LiquityContractsDev[](t.vars.numCollaterals);
        t.zappersArray = new Zappers[](t.vars.numCollaterals);
        t.vars.collaterals = new IERC20Metadata[](t.vars.numCollaterals);
        t.vars.addressesRegistries = new IAddressesRegistry[](t.vars.numCollaterals);
        t.vars.troveManagers = new ITroveManager[](t.vars.numCollaterals);

        // Deploy the first branch with WETH collateral
        t.vars.collaterals[0] = _WETH;
        (IAddressesRegistry addressesRegistry, address troveManagerAddress) =
            _deployAddressesRegistryDev(troveManagerParamsArray[0], t.quillAccessManager);
        t.vars.addressesRegistries[0] = addressesRegistry;
        t.vars.troveManagers[0] = ITroveManager(troveManagerAddress);
        for (t.vars.i = 1; t.vars.i < t.vars.numCollaterals; t.vars.i++) {
            IERC20Metadata collToken = new ERC20Faucet(
                _nameToken(t.vars.i), // _name
                _symboltoken(t.vars.i), // _symbol
                100 ether, //     _tapAmount
                1 days //         _tapPeriod
            );
            t.vars.collaterals[t.vars.i] = collToken;
            // Addresses registry and TM address
            (addressesRegistry, troveManagerAddress) =
                _deployAddressesRegistryDev(troveManagerParamsArray[t.vars.i], t.quillAccessManager);
            t.vars.addressesRegistries[t.vars.i] = addressesRegistry;
            t.vars.troveManagers[t.vars.i] = ITroveManager(troveManagerAddress);
        }

        t.collateralRegistry = CollateralRegistry(
            UnsafeUpgrades.deployUUPSProxy(
                address(new CollateralRegistry()),
                abi.encodeCall(
                    CollateralRegistry.initialize, (address(t.quillAccessManager), t.boldToken, t.sequencerSentinel)
                )
            )
        );

        t.hintHelpers = HintHelpers(
            UnsafeUpgrades.deployUUPSProxy(
                address(new HintHelpers()),
                abi.encodeCall(HintHelpers.initialize, (address(t.quillAccessManager), t.collateralRegistry))
            )
        );

        t.multiTroveGetter = MultiTroveGetter(
            UnsafeUpgrades.deployUUPSProxy(
                address(new MultiTroveGetter()),
                abi.encodeCall(MultiTroveGetter.initialize, (address(t.quillAccessManager), t.collateralRegistry))
            )
        );

        t.boldToken.setCollateralRegistry(address(t.collateralRegistry));

        DeploymentParamsDev memory params = DeploymentParamsDev({
            collToken: _WETH,
            boldToken: t.boldToken,
            collateralRegistry: t.collateralRegistry,
            weth: _WETH,
            addressesRegistry: t.vars.addressesRegistries[0],
            troveManagerAddress: address(t.vars.troveManagers[0]),
            hintHelpers: t.hintHelpers,
            multiTroveGetter: t.multiTroveGetter,
            sequencerSentinel: t.sequencerSentinel,
            troveManagerParams: troveManagerParamsArray[0]
        });
        (t.contractsArray[0], t.zappersArray[0]) = _deployAndConnectCollateralContractsDev(params);

        // Deploy the remaining branches with LST collateral
        for (t.vars.i = 1; t.vars.i < t.vars.numCollaterals; t.vars.i++) {
            DeploymentParamsDev memory params2 = DeploymentParamsDev({
                collToken: t.vars.collaterals[t.vars.i],
                boldToken: t.boldToken,
                collateralRegistry: t.collateralRegistry,
                weth: _WETH,
                addressesRegistry: t.vars.addressesRegistries[t.vars.i],
                troveManagerAddress: address(t.vars.troveManagers[t.vars.i]),
                hintHelpers: t.hintHelpers,
                multiTroveGetter: t.multiTroveGetter,
                sequencerSentinel: t.sequencerSentinel,
                troveManagerParams: troveManagerParamsArray[t.vars.i]
            });
            (t.contractsArray[t.vars.i], t.zappersArray[t.vars.i]) = _deployAndConnectCollateralContractsDev(params2);
        }

        res.contractsArray = t.contractsArray;
        res.collateralRegistry = t.collateralRegistry;
        res.boldToken = t.boldToken;
        res.hintHelpers = t.hintHelpers;
        res.multiTroveGetter = t.multiTroveGetter;
        res.WETH = _WETH;
        res.zappersArray = t.zappersArray;
        res.quillAccessManager = t.quillAccessManager;
        res.sequencerSentinel = t.sequencerSentinel;
    }

    function _deployAddressesRegistryDev(
        TroveManagerParams memory _troveManagerParams,
        QuillAccessManagerUpgradeable _quillAccessManager
    ) internal returns (IAddressesRegistry, address) {
        IAddressesRegistry addressesRegistry = new AddressesRegistry(
            address(_quillAccessManager),
            _troveManagerParams.LIQUIDATION_PENALTY_SP,
            _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        address troveManagerAddress = getAddress(
            address(this),
            getBytecode(type(TroveManagerTester).creationCode, address(addressesRegistry), _troveManagerParams),
            SALT
        );

        return (addressesRegistry, troveManagerAddress);
    }

    function _deployAndConnectCollateralContractsDev(DeploymentParamsDev memory _params)
        internal
        returns (LiquityContractsDev memory contracts, Zappers memory zappers)
    {
        LiquityContractAddresses memory addresses;
        contracts.collToken = _params.collToken;

        // Deploy all contracts, using testers for TM and PriceFeed
        contracts.addressesRegistry = _params.addressesRegistry;
        contracts.priceFeed = new PriceFeedTestnet();
        contracts.interestRouter = new MockInterestRouter();

        // Deploy Metadata
        MetadataNFT metadataNFT = deployMetadata(SALT, _params.collToken.symbol());
        addresses.metadataNFT = getAddress(
            address(this), getBytecode(type(MetadataNFT).creationCode, address(initializedFixedAssetReader)), SALT
        );
        assert(address(metadataNFT) == addresses.metadataNFT);

        // Pre-calc addresses
        addresses.borrowerOperations = getAddress(
            address(this),
            getBytecode(type(BorrowerOperationsTester).creationCode, address(contracts.addressesRegistry)),
            SALT
        );
        addresses.troveManager = _params.troveManagerAddress;
        addresses.troveNFT = getAddress(
            address(this), getBytecode(type(TroveNFT).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.stabilityPool = getAddress(
            address(this), getBytecode(type(StabilityPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.activePool = getAddress(
            address(this),
            getBytecode(
                type(ActivePool).creationCode,
                address(contracts.addressesRegistry),
                _params.troveManagerParams.SP_YIELD_SPLIT
            ),
            SALT
        );
        addresses.defaultPool = getAddress(
            address(this), getBytecode(type(DefaultPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.gasPool = getAddress(
            address(this), getBytecode(type(GasPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.collSurplusPool = getAddress(
            address(this), getBytecode(type(CollSurplusPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.sortedTroves = getAddress(
            address(this), getBytecode(type(SortedTroves).creationCode, address(contracts.addressesRegistry)), SALT
        );

        // Deploy contracts
        IAddressesRegistry.AddressVars memory addressVars = IAddressesRegistry.AddressVars({
            collToken: _params.collToken,
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
            hintHelpers: _params.hintHelpers,
            multiTroveGetter: _params.multiTroveGetter,
            collateralRegistry: _params.collateralRegistry,
            boldToken: _params.boldToken,
            sequencerSentinel: _params.sequencerSentinel,
            WETH: _params.weth
        });
        contracts.addressesRegistry.setAddresses(addressVars);

        contracts.borrowerOperations = new BorrowerOperationsTester{salt: SALT}(contracts.addressesRegistry);
        contracts.troveManager = new TroveManagerTester{salt: SALT}(
            contracts.addressesRegistry,
            _params.troveManagerParams.CCR,
            _params.troveManagerParams.MCR,
            _params.troveManagerParams.SCR,
            _params.troveManagerParams.BCR,
            _params.troveManagerParams.MIN_DEBT,
            _params.troveManagerParams.minAnnualInterestRate,
            _params.troveManagerParams.LIQUIDATION_PENALTY_SP,
            _params.troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        contracts.troveNFT = new TroveNFT{salt: SALT}(contracts.addressesRegistry);
        contracts.stabilityPool = new StabilityPool{salt: SALT}(contracts.addressesRegistry);
        contracts.activePool =
            new ActivePool{salt: SALT}(contracts.addressesRegistry, _params.troveManagerParams.SP_YIELD_SPLIT);
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

        // Connect contracts
        _params.collateralRegistry.addCollateral(_params.collToken, contracts.troveManager, type(uint256).max);

        // deploy zappers
        _deployZappers(
            contracts.addressesRegistry,
            contracts.collToken,
            _params.boldToken,
            _params.weth,
            contracts.priceFeed,
            ICurveStableswapNGPool(address(0)),
            false,
            zappers
        );
    }

    // Creates individual PriceFeed contracts based on oracle addresses.
    // Still uses mock collaterals rather than real mainnet WETH and LST addresses.

    function deployAndConnectContractsMainnet(TroveManagerParams[] memory _troveManagerParamsArray)
        public
        returns (DeploymentResultMainnet memory result)
    {
        DeploymentVarsMainnet memory vars;

        result.externalAddresses.ETHOracle = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        result.externalAddresses.RETHOracle = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
        result.externalAddresses.STETHOracle = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
        result.externalAddresses.WSTETHToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

        result.externalAddresses.RETHToken = 0xae78736Cd615f374D3085123A210448E74Fc6393;

        vars.oracleParams.ethUsdStalenessThreshold = _24_HOURS;
        vars.oracleParams.stEthUsdStalenessThreshold = _24_HOURS;
        vars.oracleParams.rEthEthStalenessThreshold = _48_HOURS;

        // Colls: WETH, WSTETH, RETH
        vars.numCollaterals = 3;
        result.contractsArray = new LiquityContracts[](vars.numCollaterals);
        result.zappersArray = new Zappers[](vars.numCollaterals);
        vars.priceFeeds = new IPriceFeed[](vars.numCollaterals);
        vars.collaterals = new IERC20Metadata[](vars.numCollaterals);
        vars.addressesRegistries = new IAddressesRegistry[](vars.numCollaterals);
        vars.troveManagers = new ITroveManager[](vars.numCollaterals);
        address troveManagerAddress;

        result.quillAccessManager = QuillAccessManagerUpgradeable(
            UnsafeUpgrades.deployUUPSProxy(
                address(new QuillAccessManagerUpgradeable()),
                abi.encodeCall(QuillAccessManagerUpgradeable.initialize, (address(this)))
            )
        );
        vars.quillAccessManager = result.quillAccessManager;

        // Price feeds
        // ETH
        vars.priceFeeds[0] = new WETHPriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.ETHOracle,
            vars.oracleParams.ethUsdStalenessThreshold
        );

        // RETH
        vars.priceFeeds[1] = new RETHPriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.ETHOracle,
            result.externalAddresses.RETHOracle,
            result.externalAddresses.RETHToken,
            vars.oracleParams.ethUsdStalenessThreshold,
            vars.oracleParams.rEthEthStalenessThreshold
        );

        // wstETH
        vars.priceFeeds[2] = new WSTETHPriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.ETHOracle,
            result.externalAddresses.STETHOracle,
            result.externalAddresses.WSTETHToken,
            vars.oracleParams.ethUsdStalenessThreshold,
            vars.oracleParams.stEthUsdStalenessThreshold
        );

        // TODO: A couple of dummy contracts to make sure the BOLD token address ends up on the correct side of the Univ3 pool// a few tests somehow if that assumption is broken
        new QuillAccessManagerUpgradeable();
        new QuillAccessManagerUpgradeable();

        // Deploy Bold
        result.boldToken = BoldToken(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BoldToken()), abi.encodeCall(BoldToken.initialize, (address(result.quillAccessManager)))
            )
        );
        console.log(address(result.boldToken));
        vars.boldTokenAddress = address(result.boldToken);
        result.sequencerSentinel = new QuillSequencerSentinelMainnet();
        vars.sequencerSentinel = result.sequencerSentinel;

        // WETH
        IWETH WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vars.collaterals[0] = WETH;
        (vars.addressesRegistries[0], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[0], result.quillAccessManager);
        vars.troveManagers[0] = ITroveManager(troveManagerAddress);

        // RETH
        vars.collaterals[1] = IERC20Metadata(0xae78736Cd615f374D3085123A210448E74Fc6393);
        (vars.addressesRegistries[1], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[1], result.quillAccessManager);
        vars.troveManagers[1] = ITroveManager(troveManagerAddress);

        // WSTETH
        vars.collaterals[2] = IERC20Metadata(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        (vars.addressesRegistries[2], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[2], result.quillAccessManager);
        vars.troveManagers[2] = ITroveManager(troveManagerAddress);

        // Deploy registry and register the TMs
        result.collateralRegistry = CollateralRegistryTester(
            UnsafeUpgrades.deployUUPSProxy(
                address(new CollateralRegistryTester()),
                abi.encodeCall(
                    CollateralRegistry.initialize,
                    (address(result.quillAccessManager), result.boldToken, result.sequencerSentinel)
                )
            )
        );

        result.hintHelpers = HintHelpers(
            UnsafeUpgrades.deployUUPSProxy(
                address(new HintHelpers()),
                abi.encodeCall(HintHelpers.initialize, (address(result.quillAccessManager), result.collateralRegistry))
            )
        );

        result.multiTroveGetter = MultiTroveGetter(
            UnsafeUpgrades.deployUUPSProxy(
                address(new MultiTroveGetter()),
                abi.encodeCall(
                    MultiTroveGetter.initialize, (address(result.quillAccessManager), result.collateralRegistry)
                )
            )
        );

        result.boldToken.setCollateralRegistry(address(result.collateralRegistry));

        ICurveStableswapNGPool usdcCurvePool = _deployCurveBoldUsdcPool(result.boldToken, true);

        // Deploy each set of core contracts
        for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
            DeploymentParamsMainnet memory params;
            params.collToken = vars.collaterals[vars.i];
            params.priceFeed = vars.priceFeeds[vars.i];
            params.boldToken = result.boldToken;
            params.collateralRegistry = result.collateralRegistry;
            params.weth = WETH;
            params.addressesRegistry = vars.addressesRegistries[vars.i];
            params.troveManagerAddress = address(vars.troveManagers[vars.i]);
            params.hintHelpers = result.hintHelpers;
            params.multiTroveGetter = result.multiTroveGetter;
            params.usdcCurvePool = usdcCurvePool;
            params.sequencerSentinel = result.sequencerSentinel;
            params.troveManagerParams = _troveManagerParamsArray[vars.i];
            (result.contractsArray[vars.i], result.zappersArray[vars.i]) =
                _deployAndConnectCollateralContractsMainnet(params);
        }
    }

    function _deployAddressesRegistryMainnet(
        TroveManagerParams memory _troveManagerParams,
        QuillAccessManagerUpgradeable quillAccessManager
    ) internal returns (IAddressesRegistry, address) {
        IAddressesRegistry addressesRegistry = new AddressesRegistry(
            address(quillAccessManager),
            _troveManagerParams.LIQUIDATION_PENALTY_SP,
            _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        address troveManagerAddress = getAddress(
            address(this),
            getBytecode(type(TroveManager).creationCode, address(addressesRegistry), _troveManagerParams),
            SALT
        );

        return (addressesRegistry, troveManagerAddress);
    }

    function _deployAndConnectCollateralContractsMainnet(DeploymentParamsMainnet memory _params)
        internal
        returns (LiquityContracts memory contracts, Zappers memory zappers)
    {
        LiquityContractAddresses memory addresses;
        contracts.collToken = _params.collToken;
        contracts.priceFeed = _params.priceFeed;
        contracts.interestRouter = new MockInterestRouter();

        contracts.addressesRegistry = _params.addressesRegistry;

        // Deploy Metadata
        MetadataNFT metadataNFT = deployMetadata(SALT, _params.collToken.symbol());
        addresses.metadataNFT = getAddress(
            address(this), getBytecode(type(MetadataNFT).creationCode, address(initializedFixedAssetReader)), SALT
        );
        assert(address(metadataNFT) == addresses.metadataNFT);

        // Pre-calc addresses
        addresses.borrowerOperations = getAddress(
            address(this),
            getBytecode(type(BorrowerOperationsTester).creationCode, address(contracts.addressesRegistry)),
            SALT
        );
        addresses.troveManager = _params.troveManagerAddress;
        addresses.troveNFT = getAddress(
            address(this), getBytecode(type(TroveNFT).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.stabilityPool = getAddress(
            address(this), getBytecode(type(StabilityPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.activePool = getAddress(
            address(this),
            getBytecode(
                type(ActivePool).creationCode,
                address(contracts.addressesRegistry),
                _params.troveManagerParams.SP_YIELD_SPLIT
            ),
            SALT
        );
        addresses.defaultPool = getAddress(
            address(this), getBytecode(type(DefaultPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.gasPool = getAddress(
            address(this), getBytecode(type(GasPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.collSurplusPool = getAddress(
            address(this), getBytecode(type(CollSurplusPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.sortedTroves = getAddress(
            address(this), getBytecode(type(SortedTroves).creationCode, address(contracts.addressesRegistry)), SALT
        );

        // Deploy contracts
        IAddressesRegistry.AddressVars memory addressVars = IAddressesRegistry.AddressVars({
            collToken: _params.collToken,
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
            hintHelpers: _params.hintHelpers,
            multiTroveGetter: _params.multiTroveGetter,
            collateralRegistry: _params.collateralRegistry,
            boldToken: _params.boldToken,
            sequencerSentinel: _params.sequencerSentinel,
            WETH: _params.weth
        });
        contracts.addressesRegistry.setAddresses(addressVars);

        contracts.borrowerOperations = new BorrowerOperationsTester{salt: SALT}(contracts.addressesRegistry);
        contracts.troveManager = new TroveManager{salt: SALT}(
            contracts.addressesRegistry,
            _params.troveManagerParams.CCR,
            _params.troveManagerParams.MCR,
            _params.troveManagerParams.SCR,
            _params.troveManagerParams.BCR,
            _params.troveManagerParams.MIN_DEBT,
            _params.troveManagerParams.minAnnualInterestRate,
            _params.troveManagerParams.LIQUIDATION_PENALTY_SP,
            _params.troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION
        );
        contracts.troveNFT = new TroveNFT{salt: SALT}(contracts.addressesRegistry);
        contracts.stabilityPool = new StabilityPool{salt: SALT}(contracts.addressesRegistry);
        contracts.activePool =
            new ActivePool{salt: SALT}(contracts.addressesRegistry, _params.troveManagerParams.SP_YIELD_SPLIT);
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
        _params.collateralRegistry.addCollateral(_params.collToken, contracts.troveManager, type(uint256).max);

        // TODO: remove this and set address in constructor as per the CREATE2 approach above
        _params.priceFeed.setAddresses(addresses.borrowerOperations);

        // deploy zappers
        _deployZappers(
            contracts.addressesRegistry,
            contracts.collToken,
            _params.boldToken,
            _params.weth,
            contracts.priceFeed,
            _params.usdcCurvePool,
            true,
            zappers
        );
    }

    function _deployZappers(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IBoldToken _boldToken,
        IWETH _weth,
        IPriceFeed _priceFeed,
        ICurveStableswapNGPool _usdcCurvePool,
        bool _mainnet,
        Zappers memory zappers // result
    ) internal virtual {
        IFlashLoanProvider flashLoanProvider = new BalancerFlashLoan();
        IExchange curveExchange = _deployCurveExchange(_collToken, _boldToken, _priceFeed, _mainnet);

        // TODO: Deploy base zappers versions with Uni V3 exchange
        bool lst = _collToken != _weth;
        if (lst) {
            zappers.gasCompZapper = new GasCompZapper(_addressesRegistry, flashLoanProvider, curveExchange);
        } else {
            zappers.wethZapper = new WETHZapper(_addressesRegistry, flashLoanProvider, curveExchange);
        }

        if (_mainnet) {
            _deployLeverageZappers(
                _addressesRegistry,
                _collToken,
                _boldToken,
                _priceFeed,
                flashLoanProvider,
                curveExchange,
                _usdcCurvePool,
                lst,
                zappers
            );
        }
    }

    function _deployCurveExchange(IERC20 _collToken, IBoldToken _boldToken, IPriceFeed _priceFeed, bool _mainnet)
        internal
        returns (IExchange)
    {
        if (!_mainnet) {
            return new CurveExchange(_collToken, _boldToken, ICurvePool(address(0)), 1, 0);
        }

        (uint256 price,) = _priceFeed.fetchPrice();

        // deploy Curve Twocrypto NG pool
        address[2] memory coins;
        coins[BOLD_TOKEN_INDEX] = address(_boldToken);
        coins[COLL_TOKEN_INDEX] = address(_collToken);
        ICurvePool curvePool = curveFactory.deploy_pool(
            "LST-Bold pool",
            "LBLD",
            coins,
            0, // implementation id
            400000, // A
            145000000000000, // gamma
            26000000, // mid_fee
            45000000, // out_fee
            230000000000000, // fee_gamma
            2000000000000, // allowed_extra_profit
            146000000000000, // adjustment_step
            600, // ma_exp_time
            price // initial_price
        );

        IExchange curveExchange = new CurveExchange(_collToken, _boldToken, curvePool, 1, 0);

        return curveExchange;
    }

    function _deployLeverageZappers(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IBoldToken _boldToken,
        IPriceFeed _priceFeed,
        IFlashLoanProvider _flashLoanProvider,
        IExchange _curveExchange,
        ICurveStableswapNGPool _usdcCurvePool,
        bool _lst,
        Zappers memory zappers // result
    ) internal {
        zappers.leverageZapperCurve =
            _deployCurveLeverageZapper(_addressesRegistry, _flashLoanProvider, _curveExchange, _lst);
        zappers.leverageZapperUniV3 =
            _deployUniV3LeverageZapper(_addressesRegistry, _collToken, _boldToken, _priceFeed, _flashLoanProvider, _lst);
        zappers.leverageZapperHybrid = _deployHybridLeverageZapper(
            _addressesRegistry, _collToken, _boldToken, _flashLoanProvider, _usdcCurvePool, _lst
        );
    }

    function _deployCurveLeverageZapper(
        IAddressesRegistry _addressesRegistry,
        IFlashLoanProvider _flashLoanProvider,
        IExchange _curveExchange,
        bool _lst
    ) internal returns (ILeverageZapper) {
        ILeverageZapper leverageZapperCurve;
        if (_lst) {
            leverageZapperCurve = new LeverageLSTZapper(_addressesRegistry, _flashLoanProvider, _curveExchange);
        } else {
            leverageZapperCurve = new LeverageWETHZapper(_addressesRegistry, _flashLoanProvider, _curveExchange);
        }

        return leverageZapperCurve;
    }

    struct UniV3Vars {
        IExchange uniV3Exchange;
        uint256 price;
        address[2] tokens;
    }

    function _deployUniV3LeverageZapper(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IBoldToken _boldToken,
        IPriceFeed _priceFeed,
        IFlashLoanProvider _flashLoanProvider,
        bool _lst
    ) internal returns (ILeverageZapper) {
        UniV3Vars memory vars;
        vars.uniV3Exchange = new UniV3Exchange(_collToken, _boldToken, UNIV3_FEE, uniV3Router);
        ILeverageZapper leverageZapperUniV3;
        if (_lst) {
            leverageZapperUniV3 = new LeverageLSTZapper(_addressesRegistry, _flashLoanProvider, vars.uniV3Exchange);
        } else {
            leverageZapperUniV3 = new LeverageWETHZapper(_addressesRegistry, _flashLoanProvider, vars.uniV3Exchange);
        }

        // Create Uni V3 pool
        (vars.price,) = _priceFeed.fetchPrice();
        if (address(_boldToken) < address(_collToken)) {
            //console2.log("b < c");
            vars.tokens[0] = address(_boldToken);
            vars.tokens[1] = address(_collToken);
        } else {
            //console2.log("c < b");
            vars.tokens[0] = address(_collToken);
            vars.tokens[1] = address(_boldToken);
        }
        uniV3PositionManager.createAndInitializePoolIfNecessary(
            vars.tokens[0], // token0,
            vars.tokens[1], // token1,
            UNIV3_FEE, // fee,
            UniV3Exchange(address(vars.uniV3Exchange)).priceToSqrtPrice(_boldToken, _collToken, vars.price) // sqrtPriceX96
        );

        return leverageZapperUniV3;
    }

    function _deployHybridLeverageZapper(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IBoldToken _boldToken,
        IFlashLoanProvider _flashLoanProvider,
        ICurveStableswapNGPool _usdcCurvePool,
        bool _lst
    ) internal returns (ILeverageZapper) {
        IExchange hybridExchange = new HybridCurveUniV3Exchange(
            _collToken,
            _boldToken,
            USDC,
            WETH_MAINNET,
            _usdcCurvePool,
            USDC_INDEX, // USDC Curve pool index
            BOLD_TOKEN_INDEX, // BOLD Curve pool index
            UNIV3_FEE_USDC_WETH,
            UNIV3_FEE_WETH_COLL,
            uniV3Router
        );

        ILeverageZapper leverageZapperHybrid;
        if (_lst) {
            leverageZapperHybrid = new LeverageLSTZapper(_addressesRegistry, _flashLoanProvider, hybridExchange);
        } else {
            leverageZapperHybrid = new LeverageWETHZapper(_addressesRegistry, _flashLoanProvider, hybridExchange);
        }

        return leverageZapperHybrid;
    }

    function _deployCurveBoldUsdcPool(IBoldToken _boldToken, bool _mainnet) internal returns (ICurveStableswapNGPool) {
        if (!_mainnet) return ICurveStableswapNGPool(address(0));

        // deploy Curve Stableswap pool
        /*
        address[2] memory coins;
        coins[BOLD_TOKEN_INDEX] = address(_boldToken);
        coins[USDC_INDEX] = address(USDC);
        ICurvePool curvePool = curveStableswapFactory.deploy_plain_pool(
            "USDC-Bold pool",
            "USDCBOLD",
            coins,
            4000, // A
            0, // asset type: USD
            1000000, // fee
            0 // implementation id
        );
        */
        // deploy Curve StableswapNG pool
        address[] memory coins = new address[](2);
        coins[BOLD_TOKEN_INDEX] = address(_boldToken);
        coins[USDC_INDEX] = address(USDC);
        uint8[] memory assetTypes = new uint8[](2); // 0: standard
        bytes4[] memory methodIds = new bytes4[](2);
        address[] memory oracles = new address[](2);
        ICurveStableswapNGPool curvePool = curveStableswapFactory.deploy_plain_pool(
            "USDC-BOLD",
            "USDCBOLD",
            coins,
            4000, // A
            1000000, // fee
            20000000000, // _offpeg_fee_multiplier
            865, // _ma_exp_time
            0, // implementation id
            assetTypes,
            methodIds,
            oracles
        );

        return curvePool;
    }

    function noOp() external pure {}
}
