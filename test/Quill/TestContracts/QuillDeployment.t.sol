// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../TestContracts/Deployment.t.sol";
import "src/Quill/SequencerSentinel/Scroll.sol";
import "src/Quill/PriceFeeds/QuillSimplePriceFeed.sol";
import "src/Quill/PriceFeeds/QuillCompositePriceFeed.sol";

contract QuillTestDeployer is TestDeployer {
    address chainlinkScrollSequencerUptimeFeed = 0x45c2b8C204568A03Dc7A2E32B71D67Fe97F908A9;

    struct DeploymentVarsQuill {
        QuillOracleParams oracleParams;
        uint256 numCollaterals;
        IERC20Metadata[] collaterals;
        IAddressesRegistry[] addressesRegistries;
        ITroveManager[] troveManagers;
        IPriceFeed[] priceFeeds;
        QuillAccessManagerUpgradeable quillAccessManager;
        ISequencerSentinel sequencerSentinel;
        bytes bytecode;
        address boldTokenAddress;
        uint256 i;
    }

    struct QuillOracleParams {
        uint256 ETH_USD_stalenessThreshold;
        uint256 WSTETH_STETH_stalenessThreshold;
        uint256 WEETH_ETH_stalenessThreshold;
        uint256 SCROLL_USD_stalenessThreshold;
    }

    struct DeploymentResultQuill {
        LiquityContracts[] contractsArray;
        QuillExternalAddresses externalAddresses;
        ICollateralRegistry collateralRegistry;
        IBoldToken quillToken;
        ISequencerSentinel sequencerSentinel;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        Zappers[] zappersArray;
        QuillAccessManagerUpgradeable quillAccessManager;
    }

    struct QuillExternalAddresses {
        address ETH_USD_Oracle;
        address WSTETH_STETH_Oracle;
        address WETH_ETH_Oracle;
        address WEETH_ETH_Oracle;
        address SCROLL_USD_Oracle;
        address WETH_Token;
        address WSTETH_Token;
        address WEETH_Token;
        address SCROLL_Token;
    }

    function _nameToken(uint256 _index) internal pure override returns (string memory) {
        if (_index == 1) return "Wrapped eETH";
        if (_index == 2) return "rswETH";
        if (_index == 3) return "Renzo Restaked ETH";
        if (_index == 4) return "KelpDao Restaked ETH";
        if (_index == 5) return "swETH";
        if (_index == 6) return "swBTC";
        if (_index == 7) return "Swell Governance Token";
        return "LST Tester";
    }

    function _symboltoken(uint256 _index) internal pure override returns (string memory) {
        if (_index == 1) return "weETH";
        if (_index == 2) return "rswETH";
        if (_index == 3) return "ezETH";
        if (_index == 4) return "rsETH";
        if (_index == 5) return "swETH";
        if (_index == 6) return "swBTC";
        if (_index == 7) return "SWELL";
        return "LST";
    }

    function deployAndConnectContractsQuill(TroveManagerParams[] memory _troveManagerParamsArray)
        public
        returns (DeploymentResultQuill memory result)
    {
        DeploymentVarsQuill memory vars;

        result.externalAddresses.ETH_USD_Oracle = 0x6bF14CB0A831078629D993FDeBcB182b21A8774C;
        result.externalAddresses.WSTETH_STETH_Oracle = 0xE61Da4C909F7d86797a0D06Db63c34f76c9bCBDC;
        result.externalAddresses.WEETH_ETH_Oracle = 0x57bd9E614f542fB3d6FeF2B744f3B813f0cc1258;
        result.externalAddresses.SCROLL_USD_Oracle = 0x26f6F7C468EE309115d19Aa2055db5A74F8cE7A5;
        result.externalAddresses.WETH_Token = 0x5300000000000000000000000000000000000004;
        result.externalAddresses.WSTETH_Token = 0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32;
        result.externalAddresses.WEETH_Token = 0x01f0a31698C4d065659b9bdC21B3610292a1c506;
        result.externalAddresses.SCROLL_Token = 0xd29687c813D741E2F938F4aC377128810E217b1b;
        vm.label(result.externalAddresses.ETH_USD_Oracle, "ETH_USD_Oracle");
        vm.label(result.externalAddresses.WSTETH_STETH_Oracle, "WSTETH_STETH_Oracle");
        vm.label(result.externalAddresses.WEETH_ETH_Oracle, "WEETH_ETH_Oracle");
        vm.label(result.externalAddresses.SCROLL_USD_Oracle, "SCROLL_USD_Oracle");
        vm.label(result.externalAddresses.WETH_Token, "WETH_Token");
        vm.label(result.externalAddresses.WSTETH_Token, "WSTETH_Token");
        vm.label(result.externalAddresses.WEETH_Token, "WEETH_Token");
        vm.label(result.externalAddresses.SCROLL_Token, "SCROLL_Token");

        vars.oracleParams.ETH_USD_stalenessThreshold = _48_HOURS;
        vars.oracleParams.WSTETH_STETH_stalenessThreshold = _48_HOURS;
        vars.oracleParams.WEETH_ETH_stalenessThreshold = _48_HOURS;
        vars.oracleParams.SCROLL_USD_stalenessThreshold = _48_HOURS;

        vars.numCollaterals = 4;
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
        // WETH
        vars.priceFeeds[0] = new QuillSimplePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.ETH_USD_Oracle,
            vars.oracleParams.ETH_USD_stalenessThreshold
        );

        // WstETH
        vars.priceFeeds[1] = new QuillCompositePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.WSTETH_STETH_Oracle,
            result.externalAddresses.ETH_USD_Oracle,
            vars.oracleParams.WSTETH_STETH_stalenessThreshold,
            vars.oracleParams.ETH_USD_stalenessThreshold
        );

        // WEETH
        vars.priceFeeds[2] = new QuillCompositePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.WEETH_ETH_Oracle,
            result.externalAddresses.ETH_USD_Oracle,
            vars.oracleParams.WEETH_ETH_stalenessThreshold,
            vars.oracleParams.ETH_USD_stalenessThreshold
        );

        // Scroll
        vars.priceFeeds[3] = new QuillSimplePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.SCROLL_USD_Oracle,
            vars.oracleParams.SCROLL_USD_stalenessThreshold
        );

        // Deploy Quill
        result.quillToken = BoldToken(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BoldToken()), abi.encodeCall(BoldToken.initialize, (address(result.quillAccessManager)))
            )
        );
        vars.boldTokenAddress = address(result.quillToken);

        result.sequencerSentinel = new QuillSequencerSentinel(
            address(vars.quillAccessManager),
            chainlinkScrollSequencerUptimeFeed,
            3600 // grace period 1h
        );
        vars.sequencerSentinel = result.sequencerSentinel;

        // WETH
        IWETH WETH = IWETH(result.externalAddresses.WETH_Token);
        vars.collaterals[0] = WETH;
        (vars.addressesRegistries[0], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[0], result.quillAccessManager);
        vars.troveManagers[0] = ITroveManager(troveManagerAddress);

        // wstETH
        vars.collaterals[1] = IERC20Metadata(result.externalAddresses.WSTETH_Token);
        (vars.addressesRegistries[1], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[1], result.quillAccessManager);
        vars.troveManagers[1] = ITroveManager(troveManagerAddress);

        // weETH
        vars.collaterals[2] = IERC20Metadata(result.externalAddresses.WEETH_Token);
        (vars.addressesRegistries[2], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[2], result.quillAccessManager);
        vars.troveManagers[2] = ITroveManager(troveManagerAddress);

        vars.collaterals[3] = IERC20Metadata(result.externalAddresses.SCROLL_Token);
        (vars.addressesRegistries[3], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[3], result.quillAccessManager);
        vars.troveManagers[3] = ITroveManager(troveManagerAddress);

        // Deploy registry and register the TMs
        result.collateralRegistry = CollateralRegistry(
            UnsafeUpgrades.deployUUPSProxy(
                address(new CollateralRegistry()),
                abi.encodeCall(
                    CollateralRegistry.initialize,
                    (address(result.quillAccessManager), result.quillToken, result.sequencerSentinel)
                )
            )
        );
        result.quillToken.setCollateralRegistry(address(result.collateralRegistry));

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

        // Deploy each set of core contracts
        for (vars.i = 0; vars.i < vars.numCollaterals; vars.i++) {
            DeploymentParamsMainnet memory params;
            params.collToken = vars.collaterals[vars.i];
            params.priceFeed = vars.priceFeeds[vars.i];
            params.boldToken = result.quillToken;
            params.collateralRegistry = result.collateralRegistry;
            params.weth = WETH;
            params.addressesRegistry = vars.addressesRegistries[vars.i];
            params.troveManagerAddress = address(vars.troveManagers[vars.i]);
            params.hintHelpers = result.hintHelpers;
            params.multiTroveGetter = result.multiTroveGetter;
            // params.usdcCurvePool = usdcCurvePool;
            params.troveManagerParams = _troveManagerParamsArray[vars.i];
            params.sequencerSentinel = result.sequencerSentinel;
            (result.contractsArray[vars.i], result.zappersArray[vars.i]) =
                _deployAndConnectCollateralContractsMainnet(params);
        }
    }

    function _deployZappers(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IBoldToken, /* _boldToken */
        IWETH _weth,
        IPriceFeed, /* _priceFeed */
        ICurveStableswapNGPool, /* _usdcCurvePool */
        bool, /* _mainnet */
        Zappers memory zappers // result
    ) internal virtual override(TestDeployer) {
        // TODO: currently skippping flash loan and exchange provider
        // until we figure out which ones to use on scroll
        // I set this to address(1) to avoid reverting on deployment
        // Issue URL: https://github.com/subvisual/quill/issues/114
        IFlashLoanProvider flashLoanProvider = IFlashLoanProvider(address(0));
        IExchange curveExchange = IExchange(address(0));

        // TODO: Deploy base zappers versions with Uni V3 exchange
        if (_collToken != _weth) {
            zappers.gasCompZapper = new GasCompZapper(_addressesRegistry, flashLoanProvider, curveExchange);
        } else {
            zappers.wethZapper = new WETHZapper(_addressesRegistry, flashLoanProvider, curveExchange);
        }

        // TODO: currently skipping leverage zappers
        // _deployLeverageZappers(
        //     _addressesRegistry,
        //     _collToken,
        //     _boldToken,
        //     _priceFeed,
        //     flashLoanProvider,
        //     curveExchange,
        //     _usdcCurvePool,
        //     lst,
        //     zappers
        // );
    }
}
