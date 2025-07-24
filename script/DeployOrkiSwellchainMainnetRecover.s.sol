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
import {initSlipstreamLiquidityPool, initSlipstreamLiquidityPoolJump, InitSlipstreamLiquidityPoolArgs} from "script/VelodromeLiquidityPools.s.sol";

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

        DeploymentResult memory r;
        r.boldToken = IBoldToken(0x0000bAa0b1678229863c0A941C1056b83a1955F5);
        r.quillAccessManager = QuillAccessManagerUpgradeable(0x55DB4a872d38eda312123e23f1c8135eE0e745CA);
        r.collateralRegistry = ICollateralRegistry(0xcE9F80A0DCD51Fb3dd4f0d6BEC3AFDcaEA10c912);
        r.hintHelpers = HintHelpers(0xD25Df935BbBB87542B2f36Dc2e3D6c315D647509);
        r.multiTroveGetter = MultiTroveGetter(0x0c2C4017C1bf6e95aaF24b0f033cb6243a43fA2f);
        r.sequencerSentinel = ISequencerSentinel(0x7dE9dc432cc064a9f69B9E183163Fa7257FFd451);

        // USDK/USDC
        InitSlipstreamLiquidityPoolArgs memory usdk_usdc_args;
        usdk_usdc_args.deployer = deployer;
        usdk_usdc_args.poolFactory = slipstreamPoolFactory;
        usdk_usdc_args.positionManager = slipstreamPositionManager;
        usdk_usdc_args.tokenA = r.boldToken;
        usdk_usdc_args.tokenB = usdc;
        usdk_usdc_args.amountADesired = 1e18;
        usdk_usdc_args.amountBDesired = 1e18;
        usdk_usdc_args.tickSpacing = 50;
        usdk_usdc_args.upscaledPrice = DECIMAL_PRECISION / USDC_PRECISION * DECIMAL_PRECISION;

        initSlipstreamLiquidityPoolJump(usdk_usdc_args);

        // USDK/ETH
        (uint256 wethPrice,) = IPriceFeed(0x030E6445a915e92b9bFCd850e76B6547249E1576).fetchPrice();

        InitSlipstreamLiquidityPoolArgs memory usdk_eth_args;
        usdk_eth_args.deployer = deployer;
        usdk_eth_args.poolFactory = slipstreamPoolFactory;
        usdk_eth_args.positionManager = slipstreamPositionManager;
        usdk_eth_args.tokenA = r.boldToken;
        usdk_eth_args.tokenB = weth;
        usdk_eth_args.amountADesired = wethPrice / 1000; // ~1.50$-2.00$
        usdk_eth_args.amountBDesired = DECIMAL_PRECISION / 1000; // 0.001 ETH
        usdk_eth_args.tickSpacing = 200;
        usdk_eth_args.upscaledPrice = wethPrice;

        initSlipstreamLiquidityPool(usdk_eth_args);

        _createZombieTrovesAsDeployer_RedeemingUSDq(r);
        vm.stopBroadcast();
    }
}


// Protocol contracts:

//   BoldToken           0x0000baa0b1678229863c0a941c1056b83a1955f5
//   CollateralRegistry  0xce9f80a0dcd51fb3dd4f0d6bec3afdcaea10c912
//   HintHelpers         0xd25df935bbbb87542b2f36dc2e3d6c315d647509
//   MultiTroveGetter    0x0c2c4017c1bf6e95aaf24b0f033cb6243a43fa2f
//   WETHTester          0x4200000000000000000000000000000000000006

// Collateral 1 contracts:

//   ActivePool          0xf709e16ceb143bd59d20a01163d2ede98148bf20
//   AddressesRegistry   0xb3af2ff1daff598e78bd9222b4bd1da459e311fa
//   BorrowerOperations  0x1753fe793030f3dc8efb71d60f26e2d6425faf26
//   CollSurplusPool     0xac380c0df91475aed6420009757ea5f74f48b6be
//   CollToken           0x4200000000000000000000000000000000000006
//   DefaultPool         0x91e535da3f586a74acbfc993d6263a27d5c9bac2
//   GasCompZapper       0x0000000000000000000000000000000000000000
//   GasPool             0x3c390c95034302a8720509c12c0501d1ff822b05
//   InterestRouter      0x9c339bb827555ae214df17b78c1aa28acee183ce
//   LeverageZapper      0x82a941fecef73a80f9d7209376b5ad05daf270eb
//   MetadataNFT         0xc964d7949f5b6e8971955dbd32c3d01cf5476775
//   PriceFeed           0x030e6445a915e92b9bfcd850e76b6547249e1576
//   SortedTroves        0x56b40c81876d45639548e1f2bcd36abae0236b99
//   StabilityPool       0x6056f2825869a58e613daa2a0554c7ed52fa606f
//   TroveManager        0xcbf2b01f4673232d84fd6c12ab5c814f18f21e66
//   TroveNFT            0x7c09e99a23d1ad4ef2808df5706403e14c6af48a
//   WethZapper          0x411b9db60c9a195537a9681b65c2019b52702ebd

// Collateral 2 contracts:

//   ActivePool          0x62b9ddeb8299e3c924510bf2b4edde4aa34b67f2
//   AddressesRegistry   0xfbad31c6e391a70556b772a8564e9f073863c8d7
//   BorrowerOperations  0x21e15dfb42db6273ee1b6544551c9287e19f4dad
//   CollSurplusPool     0xd24a565f0ccc50159ccc43a7cae41a3bd431ae28
//   CollToken           0x18d33689ae5d02649a859a1cf16c9f0563975258
//   DefaultPool         0x35cee3239926a1e03f0c14a76fa0ed04c9de3ed3
//   GasCompZapper       0x76081de80871a632ec1528f6946b505e28571df0
//   GasPool             0x72101cfd45b039c95721c8d92ce5af862b21bec9
//   InterestRouter      0x9c339bb827555ae214df17b78c1aa28acee183ce
//   LeverageZapper      0xb9a2df34871e80aed12e0754f6dba74fe1adce55
//   MetadataNFT         0x71481ce91a31e776efef65ceac286a95a874f627
//   PriceFeed           0x9a571ee9af6ad210b95b9d0ce0bbe899bbb8dbe2
//   SortedTroves        0xacd46fd1f406fe35e0f01c8cb611d1b3945d30fe
//   StabilityPool       0x66ba6d543182f3404a87f8202379212bd60ee861
//   TroveManager        0xf2a7622e1b6d1d7540d6a7248f291d0d57a51bf4
//   TroveNFT            0x617245b24877a88351354f16c7e786ffc7f44c56
//   WethZapper          0x0000000000000000000000000000000000000000

// Collateral 3 contracts:

//   ActivePool          0xb102b2116e50b491dd53946f959c9260ec872110
//   AddressesRegistry   0xff84af0a6c07998b3d14b3c6c5714b2a954504fb
//   BorrowerOperations  0xb9bf5b030b00c6750974d27f85f01bc4864f8c38
//   CollSurplusPool     0x5bffc3338460ce50dd649a055af0c58b3a12a3f5
//   CollToken           0x09341022ea237a4db1644de7ccf8fa0e489d85b7
//   DefaultPool         0xdc7c48399431b8b738ad38c76521ce70eba7aee0
//   GasCompZapper       0xb11108a21a9220025ad67bad97eec5a57a9112a6
//   GasPool             0x0d895d4c01b28414c42eda9607863d310c2156d9
//   InterestRouter      0x9c339bb827555ae214df17b78c1aa28acee183ce
//   LeverageZapper      0xe7990012a37ce68fd57797206c64bc388f87eea3
//   MetadataNFT         0x6ca4f1e972a2a46873becf0726dcaa527ae1ed11
//   PriceFeed           0xc6d940d6cd34692e42802ae30d3f7f4748309541
//   SortedTroves        0x3012539c3b4b15b8473549c9a666354d8919965d
//   StabilityPool       0x87c2e5d618d9f94bfcd36eaff7483971fede6465
//   TroveManager        0x8e58db3278c07014339e808994464a5851c2d91e
//   TroveNFT            0xf46d7d1425d6ae5fd72eed628d1fa424d7c9126c
//   WethZapper          0x0000000000000000000000000000000000000000

// Collateral 4 contracts:

//   ActivePool          0xb7977a8dea3089fc0746889da247620cd7ad523e
//   AddressesRegistry   0x9b62eddf0685ac5000824ee60f5fe5cec6f2be57
//   BorrowerOperations  0x5a93b7bb205e6b6e03e8de4a7261aba7c5cccd78
//   CollSurplusPool     0xb7dd2955cbb738a9e0fd6821d6fec317c6f70562
//   CollToken           0x2826d136f5630ada89c1678b64a61620aab77aea
//   DefaultPool         0x4a4ee8a19c60b25760fcb8a36904171fe0bf9955
//   GasCompZapper       0x6ebb3e3b96dd499b0d6b6a40204d566e962ebe05
//   GasPool             0x734dbc510c52633a7e13a85e548543228173aa7e
//   InterestRouter      0x9c339bb827555ae214df17b78c1aa28acee183ce
//   LeverageZapper      0x0cc388d37918a6bb999b3c7461fc4bc866a09aed
//   MetadataNFT         0xd8756e1f3e17193b91c2a36376b1370df1cfbd08
//   PriceFeed           0x33a391138292627630a9c06d31d5d58791ba0a98
//   SortedTroves        0xcb282162fb439a90751f2540fce4fcde792b5721
//   StabilityPool       0x7ba1d55cac848122e8d42c09cddcd26e39ae5925
//   TroveManager        0x76a93891d4856a4b4d2ea3039286520e30141fed
//   TroveNFT            0x20381f40ae69faeb2bef23a0bef6fb0a3817fb86
//   WethZapper          0x0000000000000000000000000000000000000000

// Collateral 5 contracts:

//   ActivePool          0xe65e267ed1a0d45ee3d611792a97ec2527f76eda
//   AddressesRegistry   0xfd517286c2acc4f9038f0d6db6f7dd30f3ed63f1
//   BorrowerOperations  0x3769094aaec91b6b35fb5cdc39b61e87767d0fb6
//   CollSurplusPool     0x9df8cfd3e98be64c1b815f22eb5a6af99d509b00
//   CollToken           0xa6cb988942610f6731e664379d15ffcfbf282b44
//   DefaultPool         0xfcbd0ad4bca4ecbe14f3ac23272d50a3365eaef7
//   GasCompZapper       0xba9c5cb629b86b503cd7a35362d3b39aa58633c6
//   GasPool             0xfd8666e7f61a1ceef45df76dfffcaf30770b1c07
//   InterestRouter      0x9c339bb827555ae214df17b78c1aa28acee183ce
//   LeverageZapper      0x7c752b808e463fa07902cc8df569ae5f086f75e0
//   MetadataNFT         0x242d4baded1992171eca17967bec3fe7db4cc2d3
//   PriceFeed           0xd7d8f272ce19f3390ad8ecf9805109499274c714
//   SortedTroves        0x70fe410d86ff4d2bb9ef22f724cb703b2b2f331d
//   StabilityPool       0x34d13701c7af3cbf8c0b71de5bb556fa60ea73ac
//   TroveManager        0x3adf5a24eee0c459d53af3e7ce6ebf19678ee870
//   TroveNFT            0xf9b9e5ee7364b773e2e772c29ab4e222b6f6c95e
//   WethZapper          0x0000000000000000000000000000000000000000

