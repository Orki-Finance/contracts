// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../TestContracts/Deployment.t.sol";
import "src/Quill/SequencerSentinel/Swellchain.sol";
import "src/Quill/PriceFeeds/QuillSimplePriceFeed.sol";
import "src/Quill/PriceFeeds/QuillCompositePriceFeed.sol";
import { EulerFlashLoan } from "src/Zappers/Modules/FlashLoans/EulerFlashLoan.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamSwapRouter.sol";
import "src/Zappers/Modules/Exchanges/VelodromeSlipstreamExchange.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamNonfungiblePositionManager.sol";
import { ICLFactory } from "src/Zappers/Modules/Exchanges/Slipstream/core/ICLFactory.sol";
import { ICLPool } from "src/Zappers/Modules/Exchanges/Slipstream/core/ICLPool.sol";

contract OrkiTestDeployer is TestDeployer {
    address redstoneSwellchainSequencerUptimeFeed = address(0x0);
    ISlipstreamSwapRouter constant swellchainVelodromeRouter = ISlipstreamSwapRouter(0x63951637d667f23D5251DEdc0f9123D22d8595be);
    ISlipstreamNonfungiblePositionManager constant swellchainVelodromePositionManager =
        ISlipstreamNonfungiblePositionManager(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702);
    ICLFactory slipstreamPoolFactory = ICLFactory(0x04625B046C69577EfC40e6c0Bb83CDBAfab5a55F);
    int24 constant VELODROM_TICKSPACING = 200; // velodrome works the other way around, you set the tickspacing and you have a corresponding fee. 200 ~ 3000 BPS, original in liquity codebase

    struct DeploymentVarsOrki {
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

    struct DeploymentResultOrki {
        LiquityContracts[] contractsArray;
        OrkiExternalAddresses externalAddresses;
        ICollateralRegistry collateralRegistry;
        IBoldToken orkiToken;
        ISequencerSentinel sequencerSentinel;
        HintHelpers hintHelpers;
        MultiTroveGetter multiTroveGetter;
        Zappers[] zappersArray;
        QuillAccessManagerUpgradeable quillAccessManager;
    }

    struct OrkiExternalAddresses {
        address ETH_USD_Oracle;
        address RSWETH_ETH_Oracle;
        address WETH_ETH_Oracle;
        address WEETH_ETH_Oracle;
        address SWETH_ETH_Oracle;
        address WETH_Token;
        address RSWETH_Token;
        address WEETH_Token;
        address SWETH_Token;
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

    function deployAndConnectContractsOrki(TroveManagerParams[] memory _troveManagerParamsArray)
        public
        returns (DeploymentResultOrki memory result)
    {
        DeploymentVarsOrki memory vars;

        result.externalAddresses.ETH_USD_Oracle = 0xe7f71d6a24EBc391f5ee57B867ED429EB7Bd74f4;
        result.externalAddresses.RSWETH_ETH_Oracle = 0x4BAD96DD1C7D541270a0C92e1D4e5f12EEEA7a57;
        result.externalAddresses.WEETH_ETH_Oracle = 0x3fd49f2146FE0e10c4AE7E3fE04b3d5126385Ac4;
        result.externalAddresses.SWETH_ETH_Oracle = 0x3587a73AA02519335A8a6053a97657BECe0bC2Cc;
        result.externalAddresses.WETH_Token = 0x4200000000000000000000000000000000000006;
        result.externalAddresses.RSWETH_Token = 0x18d33689AE5d02649a859A1CF16c9f0563975258;
        result.externalAddresses.WEETH_Token = 0xA6cB988942610f6731e664379D15fFcfBf282b44;
        result.externalAddresses.SWETH_Token = 0x09341022ea237a4DB1644DE7CCf8FA0e489D85B7;
        vm.label(result.externalAddresses.ETH_USD_Oracle, "ETH_USD_Oracle");
        vm.label(result.externalAddresses.RSWETH_ETH_Oracle, "RSWETH_ETH_Oracle");
        vm.label(result.externalAddresses.WEETH_ETH_Oracle, "WEETH_ETH_Oracle");
        vm.label(result.externalAddresses.SWETH_ETH_Oracle, "SWETH_ETH_Oracle");
        vm.label(result.externalAddresses.WETH_Token, "WETH_Token");
        vm.label(result.externalAddresses.RSWETH_Token, "RSWETH_Token");
        vm.label(result.externalAddresses.WEETH_Token, "WEETH_Token");
        vm.label(result.externalAddresses.SWETH_Token, "SWETH_Token");

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
            _48_HOURS
        );

        // rswETH
        vars.priceFeeds[1] = new QuillCompositePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.RSWETH_ETH_Oracle,
            result.externalAddresses.ETH_USD_Oracle,
            _48_HOURS,
            _48_HOURS
        );

        // WEETH
        vars.priceFeeds[2] = new QuillCompositePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.WEETH_ETH_Oracle,
            result.externalAddresses.ETH_USD_Oracle,
            _48_HOURS,
            _48_HOURS
        );

        // sweth
        vars.priceFeeds[3] = new QuillCompositePriceFeed(
            address(result.quillAccessManager),
            result.externalAddresses.SWETH_ETH_Oracle,
            result.externalAddresses.ETH_USD_Oracle,
            _48_HOURS,
            _48_HOURS
        );

        // Deploy Orki
        result.orkiToken = BoldToken(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BoldToken()), abi.encodeCall(BoldToken.initialize, (address(result.quillAccessManager)))
            )
        );
        vars.boldTokenAddress = address(result.orkiToken);

        result.sequencerSentinel = new QuillSequencerSentinel(
            address(vars.quillAccessManager),
            redstoneSwellchainSequencerUptimeFeed,
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
        vars.collaterals[1] = IERC20Metadata(result.externalAddresses.RSWETH_Token);
        (vars.addressesRegistries[1], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[1], result.quillAccessManager);
        vars.troveManagers[1] = ITroveManager(troveManagerAddress);

        // weETH
        vars.collaterals[2] = IERC20Metadata(result.externalAddresses.WEETH_Token);
        (vars.addressesRegistries[2], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[2], result.quillAccessManager);
        vars.troveManagers[2] = ITroveManager(troveManagerAddress);

        vars.collaterals[3] = IERC20Metadata(result.externalAddresses.SWETH_Token);
        (vars.addressesRegistries[3], troveManagerAddress) =
            _deployAddressesRegistryMainnet(_troveManagerParamsArray[3], result.quillAccessManager);
        vars.troveManagers[3] = ITroveManager(troveManagerAddress);

        // Deploy registry and register the TMs
        result.collateralRegistry = CollateralRegistry(
            UnsafeUpgrades.deployUUPSProxy(
                address(new CollateralRegistry()),
                abi.encodeCall(
                    CollateralRegistry.initialize,
                    (address(result.quillAccessManager), result.orkiToken, result.sequencerSentinel)
                )
            )
        );
        result.orkiToken.setCollateralRegistry(address(result.collateralRegistry));

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
            params.boldToken = result.orkiToken;
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

    // function _deployZappers(
    //     IAddressesRegistry _addressesRegistry,
    //     IERC20 _collToken,
    //     IBoldToken, /* _boldToken */
    //     IWETH _weth,
    //     IPriceFeed, /* _priceFeed */
    //     ICurveStableswapNGPool, /* _usdcCurvePool */
    //     bool, /* _mainnet */
    //     Zappers memory zappers // result
    // ) internal virtual override(TestDeployer) {
    //     IFlashLoanProvider flashLoanProvider = IFlashLoanProvider(address(0));
    //     IExchange curveExchange = IExchange(address(0));

    //     // TODO: Deploy base zappers versions with Uni V3 exchange
    //     if (_collToken != _weth) {
    //         zappers.gasCompZapper = new GasCompZapper(_addressesRegistry, flashLoanProvider, curveExchange);
    //     } else {
    //         zappers.wethZapper = new WETHZapper(_addressesRegistry, flashLoanProvider, curveExchange);
    //     }

    //     // TODO: currently skipping leverage zappers
    //     // _deployLeverageZappers(
    //     //     _addressesRegistry,
    //     //     _collToken,
    //     //     _boldToken,
    //     //     _priceFeed,
    //     //     flashLoanProvider,
    //     //     curveExchange,
    //     //     _usdcCurvePool,
    //     //     lst,
    //     //     zappers
    //     // );
    // }

    // temporary
    function mappingCollToVault(address coll) private pure returns (address vault) {
        //weth
        if ( coll == address(0x4200000000000000000000000000000000000006) ) 
            vault = address(0x49C077B74292aA8F589d39034Bf9C1Ed1825a608);
        //rsweth
        if ( coll == address(0x18d33689AE5d02649a859A1CF16c9f0563975258) ) 
            vault = address(0x1773002742A2bCc7666e38454F761CE8fe613DE5);
        //sweth
        if ( coll == address(0x09341022ea237a4DB1644DE7CCf8FA0e489D85B7) ) 
            vault = address(0xf34253Ec3Dd0cb39C29cF5eeb62161FB350A9d14);
        //weeth
        if ( coll == address(0xA6cB988942610f6731e664379D15fFcfBf282b44) ) 
            vault = address(0x10D0D11A8B693F4E3e33d09BBab7D4aFc3C03ef3);
        require(vault != address(0x0), "Unknown collateral");
    }

    function _deployZappers(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IBoldToken _boldToken,
        IWETH _weth,
        IPriceFeed _priceFeed,
        ICurveStableswapNGPool, /* _usdcCurvePool */
        bool _mainnet,
        Zappers memory zappers // result
    ) internal virtual override(TestDeployer) {
        IFlashLoanProvider flashLoanProvider = new EulerFlashLoan(mappingCollToVault(address(_collToken)), address(_collToken));
        UniV3Vars memory vars = _deployUniV3Scroll(_boldToken, _collToken, _priceFeed, _mainnet);
        bool lst = _collToken != _weth;

        if (_mainnet) {
            if (lst) {
                zappers.gasCompZapper = new GasCompZapper(_addressesRegistry, flashLoanProvider, vars.uniV3Exchange);
            } else {
                zappers.wethZapper = new WETHZapper(_addressesRegistry, flashLoanProvider, vars.uniV3Exchange);
            }

            if (lst) {
                zappers.leverageZapperUniV3 = new LeverageLSTZapper(_addressesRegistry, flashLoanProvider, vars.uniV3Exchange);
            } else {
                zappers.leverageZapperUniV3 = new LeverageWETHZapper(_addressesRegistry, flashLoanProvider, vars.uniV3Exchange);
            }
        }
    }

    function _deployUniV3Scroll(
        IBoldToken _boldToken,
        IERC20 _collToken,
        IPriceFeed _priceFeed,
        bool _mainnet
    ) private returns (UniV3Vars memory vars) {
        vars.uniV3Exchange = new VelodromeSlipstreamExchange(_collToken, _boldToken, VELODROM_TICKSPACING, swellchainVelodromeRouter);
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
        if(_mainnet) {
            createAndInitializePoolIfNecessary(
                vars.tokens[0], // token0,
                vars.tokens[1], // token1,
                VELODROM_TICKSPACING, // tickspacing,
                UniV3Exchange(address(vars.uniV3Exchange)).priceToSqrtPrice(_boldToken, _collToken, vars.price) // sqrtPriceX96
            );
        }
    } 

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) private returns (address pool) {
        require(token0 < token1);
        pool = slipstreamPoolFactory.getPool(token0, token1, tickSpacing);
        slipstreamPoolFactory.tickSpacingToFee(tickSpacing);

        if (pool == address(0)) {
            pool = slipstreamPoolFactory.createPool(token0, token1, tickSpacing, sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , ) = ICLPool(pool).slot0();
            require(sqrtPriceX96Existing != 0, "createAndInitializePoolIfNecessary: something went wrong");
        }
    }

}
