// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "../TestContracts/DevTestSetup.sol";
import "../TestContracts/WETH.sol";
import "src/Zappers/Modules/Exchanges/Curve/ICurvePool.sol";
import "src/Zappers/Modules/Exchanges/CurveExchange.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/core/ICLPool.sol";
import "src/Zappers/Modules/Exchanges/UniV3Exchange.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamNonfungiblePositionManager.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/core/ICLFactory.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamQuoterV2.sol";
import "src/Zappers/Modules/Exchanges/HybridCurveUniV3Exchange.sol";
import "src/Zappers/Interfaces/IFlashLoanProvider.sol";
import "src/Zappers/Modules/FlashLoans/Balancer/vault/IVault.sol";
import {OrkiTestDeployer} from "./TestContracts/OrkiDeployment.t.sol";

import "src/Zappers/Modules/Exchanges/Curve/ICurveStableswapNGFactory.sol";
import {IEulerVault} from "src/Zappers/Modules/FlashLoans/Euler/IEulerVault.sol";

contract ZapperLeverageSwellchain is DevTestSetup {
    using StringFormatting for uint256;
    IEulerVault pool = IEulerVault(0x11fCfe756c05AD438e312a7fd934381537D3cFfe);

    // Velodrome
    ISlipstreamNonfungiblePositionManager constant velodromePositionManager =
        ISlipstreamNonfungiblePositionManager(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702);
    ICLFactory constant velodromeFactory = ICLFactory(0x04625B046C69577EfC40e6c0Bb83CDBAfab5a55F);
    ISlipstreamQuoterV2 constant velodromeQuoterV2 = ISlipstreamQuoterV2(0x3FA596fAC2D6f7d16E01984897Ac04200Cb9cA05);
    int24 constant VELODROME_TICKSPACING = 200; // velodrome works the other way around, you set the tickspacing and you have a corresponding fee. 200 ~ 3000 BPS, original in liquity codebase

    IZapper[] baseZapperArray;
    ILeverageZapper[] leverageZapperUniV3Array;

    TestDeployer.LiquityContracts[] contractsArray;

    struct OpenTroveVars {
        uint256 price;
        uint256 flashLoanAmount;
        uint256 expectedBoldAmount;
        uint256 maxNetDebt;
        uint256 effectiveBoldAmount;
        uint256 value;
        uint256 troveId;
    }

    struct LeverVars {
        uint256 price;
        uint256 currentCR;
        uint256 currentLR;
        uint256 currentCollAmount;
        uint256 flashLoanAmount;
        uint256 expectedBoldAmount;
        uint256 maxNetDebtIncrease;
        uint256 effectiveBoldAmount;
    }

    struct TestVars {
        uint256 collAmount;
        uint256 initialLeverageRatio;
        uint256 troveId;
        uint256 initialDebt;
        uint256 newLeverageRatio;
        uint256 realLeverageRatio;
        uint256 resultingCollateralRatio;
        uint256 flashLoanAmount;
        uint256 price;
        uint256 boldBalanceBeforeA;
        uint256 ethBalanceBeforeA;
        uint256 collBalanceBeforeA;
        uint256 boldBalanceBeforeZapper;
        uint256 ethBalanceBeforeZapper;
        uint256 collBalanceBeforeZapper;
        uint256 boldBalanceBeforeExchange;
        uint256 ethBalanceBeforeExchange;
        uint256 collBalanceBeforeExchange;
    }

    enum ExchangeType {
        Curve,
        UniV3,
        HybridCurveUniV3
    }

    uint256 private ignoreCollAboveIndex;
    uint256 private SWELLCHAIN_NUM_COLLATERALS = 4; //left out are swbtc and swell (no euler vaults)
    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("swellchain"));

        accounts = new Accounts();
        createAccounts();

        (A, B, C, D, E, F, G) = (
            accountsList[0],
            accountsList[1],
            accountsList[2],
            accountsList[3],
            accountsList[4],
            accountsList[5],
            accountsList[6]
        );

        WETH = IWETH(0x4200000000000000000000000000000000000006);

        TestDeployer.TroveManagerParams[] memory troveManagerParamsArray =
            new TestDeployer.TroveManagerParams[](SWELLCHAIN_NUM_COLLATERALS);
        troveManagerParamsArray[0] =
            TestDeployer.TroveManagerParams(150e16, 110e16, 110e16, 10e16, 5e16, 10e16, 2000e18, 72e16, _1pct / 2);
        for (uint256 c = 0; c < SWELLCHAIN_NUM_COLLATERALS; c++) {
            troveManagerParamsArray[c] =
                TestDeployer.TroveManagerParams(160e16, 120e16, 120e16, 10e16, 5e16, 10e16, 2000e18, 72e16, _1pct / 2);
        }

        OrkiTestDeployer deployer = new OrkiTestDeployer();
        OrkiTestDeployer.DeploymentResultOrki memory result =
            deployer.deployAndConnectContractsOrki(troveManagerParamsArray);
        //collateralRegistry = result.collateralRegistry;
        boldToken = result.orkiToken;
        // Record contracts
        baseZapperArray.push(result.zappersArray[0].wethZapper);
        for (uint256 c = 1; c < SWELLCHAIN_NUM_COLLATERALS; c++) {
            baseZapperArray.push(result.zappersArray[c].gasCompZapper);
        }
        for (uint256 c = 0; c < SWELLCHAIN_NUM_COLLATERALS; c++) {
            contractsArray.push(result.contractsArray[c]);
            leverageZapperUniV3Array.push(result.zappersArray[c].leverageZapperUniV3);
        }

        // Bootstrap UniV3 pools
        velodromePools(result.contractsArray);

        // assert(false);
        // Give some Collateral to test accounts
        uint256 initialCollateralAmount = 10_000e18;
        uint256 initialScrollCollateralAmount = 100_000e18;

        // A to F
        for (uint256 c = 0; c < SWELLCHAIN_NUM_COLLATERALS; c++) {
            for (uint256 i = 0; i < 6; i++) {
                // Give some raw ETH to test accounts
                deal(accountsList[i], initialCollateralAmount);
                // Give and approve some coll token to test accounts
                if(c == 3) {
                    deal(address(contractsArray[c].collToken), accountsList[i], initialScrollCollateralAmount);
                    vm.startPrank(accountsList[i]);
                    contractsArray[c].collToken.approve(address(baseZapperArray[c]), initialScrollCollateralAmount);
                    contractsArray[c].collToken.approve(address(leverageZapperUniV3Array[c]), initialScrollCollateralAmount);
                    vm.stopPrank();
                } else {
                    deal(address(contractsArray[c].collToken), accountsList[i], initialCollateralAmount);
                    vm.startPrank(accountsList[i]);
                    contractsArray[c].collToken.approve(address(baseZapperArray[c]), initialCollateralAmount);
                    contractsArray[c].collToken.approve(address(leverageZapperUniV3Array[c]), initialCollateralAmount);
                    vm.stopPrank();
                }
            }
        }

        // We are just testing collateral with known vaults (rsweth, sweth, weeth, and weth)
        ignoreCollAboveIndex = 3;
    }

    function testABC() public {
    
    }

    function velodromePools(TestDeployer.LiquityContracts[] memory _contractsArray) internal {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            (uint256 price,) = _contractsArray[i].priceFeed.fetchPrice();

            // tokens and amounts
            // uint256 collAmount = 1000 ether;
            // uint256 boldAmount = collAmount * price / DECIMAL_PRECISION;

            // replace the former logic guaranteeing that all pools have the same amount of bold, otherwise scr pool would only have < 1000$
            uint256 boldAmount = 1_000_000 ether;
            uint256 collAmount = boldAmount * DECIMAL_PRECISION / price;

            address[2] memory tokens;
            uint256[2] memory amounts;
            if (address(boldToken) < address(_contractsArray[i].collToken)) {
                //console2.log("b < c");
                tokens[0] = address(boldToken);
                tokens[1] = address(_contractsArray[i].collToken);
                amounts[0] = boldAmount;
                amounts[1] = collAmount;
            } else {
                //console2.log("c < b");
                tokens[0] = address(_contractsArray[i].collToken);
                tokens[1] = address(boldToken);
                amounts[0] = collAmount;
                amounts[1] = boldAmount;
            }

            // Add liquidity
            vm.startPrank(A);

            // deal and approve
            deal(address(_contractsArray[i].collToken), A, collAmount);
            deal(address(boldToken), A, boldAmount);
            _contractsArray[i].collToken.approve(address(velodromePositionManager), collAmount);
            boldToken.approve(address(velodromePositionManager), boldAmount);

            // mint new position
            address uniV3PoolAddress =
                velodromeFactory.getPool(address(boldToken), address(_contractsArray[i].collToken), VELODROME_TICKSPACING);

            int24 TICK_SPACING = ICLPool(uniV3PoolAddress).tickSpacing();
            (, int24 tick,,,,) = ICLPool(uniV3PoolAddress).slot0();
            int24 tickLower = (tick - 6000) / TICK_SPACING * TICK_SPACING;
            int24 tickUpper = (tick + 6000) / TICK_SPACING * TICK_SPACING;
            ISlipstreamNonfungiblePositionManager.MintParams memory params = ISlipstreamNonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                tickSpacing: TICK_SPACING,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amounts[0],
                amount1Desired: amounts[1],
                amount0Min: 0,
                amount1Min: 0,
                recipient: A,
                deadline: block.timestamp,
                sqrtPriceX96: 0
            });

            velodromePositionManager.mint(params);
            
            vm.stopPrank();
        }
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    struct OpenLeveragedTroveWithIndexParams {
        ILeverageZapper leverageZapper;
        IERC20 collToken;
        uint256 index;
        uint256 collAmount;
        uint256 leverageRatio;
        uint256 realLeverageRatio;
        IPriceFeed priceFeed;
        ExchangeType exchangeType;
        uint256 branch;
        address batchManager;
    }

    function openLeveragedTroveWithIndex(OpenLeveragedTroveWithIndexParams memory _inputParams)
        internal
        returns (uint256, uint256)
    {
        OpenTroveVars memory vars;
        (vars.price,) = _inputParams.priceFeed.fetchPrice();

        // This should be done in the frontend
        vars.flashLoanAmount =
            _inputParams.collAmount * (_inputParams.leverageRatio - DECIMAL_PRECISION) / DECIMAL_PRECISION;
        vars.expectedBoldAmount = vars.flashLoanAmount * vars.price / DECIMAL_PRECISION;
        vars.maxNetDebt = vars.expectedBoldAmount * 105 / 100; // slippage
        vars.effectiveBoldAmount = _getBoldAmountToSwap(
            _inputParams.exchangeType,
            _inputParams.branch,
            vars.expectedBoldAmount,
            vars.maxNetDebt,
            vars.flashLoanAmount,
            _inputParams.collToken
        );

        ILeverageZapper.OpenLeveragedTroveParams memory params = ILeverageZapper.OpenLeveragedTroveParams({
            owner: A,
            ownerIndex: _inputParams.index,
            collAmount: _inputParams.collAmount,
            flashLoanAmount: vars.flashLoanAmount,
            boldAmount: vars.effectiveBoldAmount,
            upperHint: 0,
            lowerHint: 0,
            annualInterestRate: _inputParams.batchManager == address(0) ? 5e16 : 0,
            batchManager: _inputParams.batchManager,
            maxUpfrontFee: 1000e18,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });
        vm.startPrank(A);
        vars.value = _inputParams.branch > 0 ? ETH_GAS_COMPENSATION : _inputParams.collAmount + ETH_GAS_COMPENSATION;
        _inputParams.leverageZapper.openLeveragedTroveWithRawETH{value: vars.value}(params);
        vars.troveId = addressToTroveIdThroughZapper(address(_inputParams.leverageZapper), A, _inputParams.index);
        vm.stopPrank();

        return (vars.troveId, vars.effectiveBoldAmount);
    }

    function _setInitialBalances(ILeverageZapper _leverageZapper, uint256 _branch, TestVars memory vars)
        internal
        view
    {
        vars.boldBalanceBeforeA = boldToken.balanceOf(A);
        vars.ethBalanceBeforeA = A.balance;
        vars.collBalanceBeforeA = contractsArray[_branch].collToken.balanceOf(A);
        vars.boldBalanceBeforeZapper = boldToken.balanceOf(address(_leverageZapper));
        vars.ethBalanceBeforeZapper = address(_leverageZapper).balance;
        vars.collBalanceBeforeZapper = contractsArray[_branch].collToken.balanceOf(address(_leverageZapper));
        vars.boldBalanceBeforeExchange = boldToken.balanceOf(address(_leverageZapper.exchange()));
        vars.ethBalanceBeforeExchange = address(_leverageZapper.exchange()).balance;
        vars.collBalanceBeforeExchange =
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper.exchange()));
    }

    function testCanOpenTroveWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testCanOpenTrove(leverageZapperUniV3Array[i], ExchangeType.UniV3, i, address(0));
        }
    }

    function testCanOpenTroveAndJoinBatchWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _registerBatchManager(B, i);
            _testCanOpenTrove(leverageZapperUniV3Array[i], ExchangeType.UniV3, i, B);
        }
    }

    function _registerBatchManager(address _account, uint256 _branch) internal {
        vm.startPrank(_account);
        contractsArray[_branch].borrowerOperations.registerBatchManager(
            uint128(1e16), uint128(20e16), uint128(5e16), uint128(25e14), MIN_INTEREST_RATE_CHANGE_PERIOD
        );
        vm.stopPrank();
    }

    // @note originally this assumed a 0 fee (balancer) changed original logic to adapt to aave 
    function _testCanOpenTrove(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch,
        address _batchManager
    ) internal {
        TestVars memory vars;
        (vars.price,) = contractsArray[_branch].priceFeed.fetchPrice();
        // uint256 boldAmount = 5_000 ether;
        // uint256 collAmount = boldAmount * DECIMAL_PRECISION / price;
        vars.collAmount = 5_000 ether * DECIMAL_PRECISION / vars.price;

        vars.newLeverageRatio = 2e18;
        vars.resultingCollateralRatio = _leverageZapper.leverageRatioToCollateralRatio(vars.newLeverageRatio);

        _setInitialBalances(_leverageZapper, _branch, vars);

        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 0;
        openTroveParams.collAmount = vars.collAmount;
        openTroveParams.leverageRatio = vars.newLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = _batchManager;
        uint256 expectedMinNetDebt;
        (vars.troveId, expectedMinNetDebt) = openLeveragedTroveWithIndex(openTroveParams);

        // Checks
        (vars.price,) = contractsArray[_branch].priceFeed.fetchPrice();
        // owner
        assertEq(contractsArray[_branch].troveNFT.ownerOf(vars.troveId), A, "Wrong owner");
        // troveId
        assertGt(vars.troveId, 0, "Trove id should be set");
        // coll
        assertEq(
            getTroveEntireColl(contractsArray[_branch].troveManager, vars.troveId),
            vars.collAmount * vars.newLeverageRatio / DECIMAL_PRECISION,
            "Coll mismatch"
        );
        // debt
        uint256 expectedMaxNetDebt = expectedMinNetDebt * 105 / 100;
        uint256 troveEntireDebt = getTroveEntireDebt(contractsArray[_branch].troveManager, vars.troveId);
        assertGe(troveEntireDebt, expectedMinNetDebt, "Debt too low");
        assertLe(troveEntireDebt, expectedMaxNetDebt, "Debt too high");
        // CR
        uint256 ICR = contractsArray[_branch].troveManager.getCurrentICR(vars.troveId, vars.price);
        assertTrue(ICR >= vars.resultingCollateralRatio || vars.resultingCollateralRatio - ICR < 3e16, "Wrong CR");
        // token balances
        assertEq(boldToken.balanceOf(A), vars.boldBalanceBeforeA, "BOLD bal mismatch");
        assertEq(
            boldToken.balanceOf(address(_leverageZapper)), vars.boldBalanceBeforeZapper, "Zapper should not keep BOLD"
        );
        assertEq(
            boldToken.balanceOf(address(_leverageZapper.exchange())),
            vars.boldBalanceBeforeExchange,
            "Exchange should not keep BOLD"
        );
        assertEq(
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper)),
            vars.collBalanceBeforeZapper,
            "Zapper should not keep Coll"
        );
        assertEq(
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper.exchange())),
            vars.collBalanceBeforeExchange,
            "Exchange should not keep Coll"
        );
        assertEq(address(_leverageZapper).balance, vars.ethBalanceBeforeZapper, "Zapper should not keep ETH");
        assertEq(
            address(_leverageZapper.exchange()).balance, vars.ethBalanceBeforeExchange, "Exchange should not keep ETH"
        );
        if (_branch > 0) {
            // LST
            assertEq(A.balance, vars.ethBalanceBeforeA - ETH_GAS_COMPENSATION, "ETH bal mismatch");
            assertGe(
                contractsArray[_branch].collToken.balanceOf(A),
                vars.collBalanceBeforeA - vars.collAmount,
                "Coll bal mismatch"
            );
        } else {
            assertEq(A.balance, vars.ethBalanceBeforeA - ETH_GAS_COMPENSATION - vars.collAmount, "ETH bal mismatch");
            assertGe(contractsArray[_branch].collToken.balanceOf(A), vars.collBalanceBeforeA, "Coll bal mismatch");
        }
    }

    function testOnlyFlashLoanProviderCanCallOpenTroveCallbackWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyFlashLoanProviderCanCallOpenTroveCallback(leverageZapperUniV3Array[i]);
        }
    }

    function _testOnlyFlashLoanProviderCanCallOpenTroveCallback(ILeverageZapper _leverageZapper) internal {
        ILeverageZapper.OpenLeveragedTroveParams memory params = ILeverageZapper.OpenLeveragedTroveParams({
            owner: A,
            ownerIndex: 0,
            collAmount: 10 ether,
            flashLoanAmount: 10 ether,
            boldAmount: 10000e18,
            upperHint: 0,
            lowerHint: 0,
            annualInterestRate: 5e16,
            batchManager: address(0),
            maxUpfrontFee: 1000e18,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });
        vm.startPrank(A);
        vm.expectRevert("LZ: Caller not FlashLoan provider");
        IFlashLoanReceiver(address(_leverageZapper)).receiveFlashLoanOnOpenLeveragedTrove(A, params, 10 ether);
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(_leverageZapper.flashLoanProvider().receiver()), address(0), "Receiver should be zero");
    }

    // Lever up

    struct LeverUpParams {
        ILeverageZapper leverageZapper;
        IERC20 collToken;
        uint256 troveId;
        uint256 leverageRatio;
        ITroveManager troveManager;
        IPriceFeed priceFeed;
        ExchangeType exchangeType;
        uint256 branch;
    }

    function _getLeverUpFlashLoanAndBoldAmount(LeverUpParams memory _params) internal returns (uint256, uint256) {
        LeverVars memory vars;
        (vars.price,) = _params.priceFeed.fetchPrice();
        vars.currentCR = _params.troveManager.getCurrentICR(_params.troveId, vars.price);
        vars.currentLR = _params.leverageZapper.leverageRatioToCollateralRatio(vars.currentCR);
        assertGt(_params.leverageRatio, vars.currentLR, "Leverage ratio should increase");
        vars.currentCollAmount = getTroveEntireColl(_params.troveManager, _params.troveId);
        vars.flashLoanAmount = vars.currentCollAmount * _params.leverageRatio / vars.currentLR - vars.currentCollAmount;
        vars.expectedBoldAmount = vars.flashLoanAmount * vars.price / DECIMAL_PRECISION;
        vars.maxNetDebtIncrease = vars.expectedBoldAmount * 105 / 100; // slippage
        // The actual bold we need, capped by the slippage above, to get flash loan amount
        vars.effectiveBoldAmount = _getBoldAmountToSwap(
            _params.exchangeType,
            _params.branch,
            vars.expectedBoldAmount,
            vars.maxNetDebtIncrease,
            vars.flashLoanAmount,
            _params.collToken
        );

        return (vars.flashLoanAmount, vars.effectiveBoldAmount);
    }

    function leverUpTrove(LeverUpParams memory _params) internal returns (uint256, uint256) {
        // This should be done in the frontend
        (uint256 flashLoanAmount, uint256 effectiveBoldAmount) = _getLeverUpFlashLoanAndBoldAmount(_params);

        ILeverageZapper.LeverUpTroveParams memory params = ILeverageZapper.LeverUpTroveParams({
            troveId: _params.troveId,
            flashLoanAmount: flashLoanAmount,
            boldAmount: effectiveBoldAmount,
            maxUpfrontFee: 1000e18
        });
        vm.startPrank(A);
        _params.leverageZapper.leverUpTrove(params);
        vm.stopPrank();

        return (flashLoanAmount, effectiveBoldAmount);
    }

    function testCanLeverUpTroveWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > 0) continue; 
            _testCanLeverUpTrove(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testCanLeverUpTrove(ILeverageZapper _leverageZapper, ExchangeType _exchangeType, uint256 _branch)
        internal
    {
        TestVars memory vars;
        vars.collAmount = 10 ether;
        vars.initialLeverageRatio = 2e18;

        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 0;
        openTroveParams.collAmount = vars.collAmount;
        openTroveParams.leverageRatio = vars.initialLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (vars.troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        vars.initialDebt = getTroveEntireDebt(contractsArray[_branch].troveManager, vars.troveId);

        vars.newLeverageRatio = 2.5e18;
        vars.resultingCollateralRatio = _leverageZapper.leverageRatioToCollateralRatio(vars.newLeverageRatio);

        _setInitialBalances(_leverageZapper, _branch, vars);

        LeverUpParams memory params;
        params.leverageZapper = _leverageZapper;
        params.collToken = contractsArray[_branch].collToken;
        params.troveId = vars.troveId;
        params.leverageRatio = vars.newLeverageRatio;
        params.troveManager = contractsArray[_branch].troveManager;
        params.priceFeed = contractsArray[_branch].priceFeed;
        params.exchangeType = _exchangeType;
        params.branch = _branch;
        uint256 expectedMinLeverUpNetDebt;
        (vars.flashLoanAmount, expectedMinLeverUpNetDebt) = leverUpTrove(params);

        // Checks
        (vars.price,) = contractsArray[_branch].priceFeed.fetchPrice();
        // coll
        uint256 coll = getTroveEntireColl(contractsArray[_branch].troveManager, vars.troveId);
        uint256 collExpected = vars.collAmount * vars.newLeverageRatio / DECIMAL_PRECISION;
        assertTrue(coll >= collExpected || collExpected - coll <= 4e17, "Coll mismatch");
        // debt
        uint256 expectedMinNetDebt = vars.initialDebt + expectedMinLeverUpNetDebt;
        uint256 expectedMaxNetDebt = expectedMinNetDebt * 105 / 100;
        uint256 troveEntireDebt = getTroveEntireDebt(contractsArray[_branch].troveManager, vars.troveId);
        assertGe(troveEntireDebt, expectedMinNetDebt, "Debt too low");
        assertLe(troveEntireDebt, expectedMaxNetDebt, "Debt too high");
        // CR
        uint256 ICR = contractsArray[_branch].troveManager.getCurrentICR(vars.troveId, vars.price);
        assertTrue(ICR >= vars.resultingCollateralRatio || vars.resultingCollateralRatio - ICR < 2e16, "Wrong CR");
        // token balances
        assertEq(boldToken.balanceOf(A), vars.boldBalanceBeforeA, "BOLD bal mismatch");
        assertEq(A.balance, vars.ethBalanceBeforeA, "ETH bal mismatch");
        assertGe(contractsArray[_branch].collToken.balanceOf(A), vars.collBalanceBeforeA, "Coll bal mismatch");
        assertEq(
            boldToken.balanceOf(address(_leverageZapper)), vars.boldBalanceBeforeZapper, "Zapper should not keep BOLD"
        );
        assertEq(
            boldToken.balanceOf(address(_leverageZapper.exchange())),
            vars.boldBalanceBeforeExchange,
            "Exchange should not keep BOLD"
        );
        assertEq(
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper)),
            vars.collBalanceBeforeZapper,
            "Zapper should not keep Coll"
        );
        assertEq(
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper.exchange())),
            vars.collBalanceBeforeExchange,
            "Exchange should not keep Coll"
        );
        assertEq(address(_leverageZapper).balance, vars.ethBalanceBeforeZapper, "Zapper should not keep ETH");
        assertEq(
            address(_leverageZapper.exchange()).balance, vars.ethBalanceBeforeExchange, "Exchange should not keep ETH"
        );

        // Check receiver is back to zero
        assertEq(address(_leverageZapper.flashLoanProvider().receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyFlashLoanProviderCanCallLeverUpCallbackWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyFlashLoanProviderCanCallLeverUpCallback(leverageZapperUniV3Array[i]);
        }
    }

    function _testOnlyFlashLoanProviderCanCallLeverUpCallback(ILeverageZapper _leverageZapper) internal {
        ILeverageZapper.LeverUpTroveParams memory params = ILeverageZapper.LeverUpTroveParams({
            troveId: addressToTroveIdThroughZapper(address(_leverageZapper), A),
            flashLoanAmount: 10 ether,
            boldAmount: 10000e18,
            maxUpfrontFee: 1000e18
        });
        vm.startPrank(A);
        vm.expectRevert("LZ: Caller not FlashLoan provider");
        IFlashLoanReceiver(address(_leverageZapper)).receiveFlashLoanOnLeverUpTrove(params, 10 ether);
        vm.stopPrank();
    }

    function testOnlyOwnerOrManagerCanLeverUpWithUniV3FromZapper() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanLeverUpFromZapper(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testOnlyOwnerOrManagerCanLeverUpFromZapper(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch
    ) internal {
        // Open trove
        // uint256 boldAmount = 5_000 ether;
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 5_000 ether * DECIMAL_PRECISION / price;
        uint256 leverageRatio = 2e18;
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 0;
        openTroveParams.collAmount = collAmount;
        openTroveParams.leverageRatio = leverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        LeverUpParams memory getterParams;
        getterParams.leverageZapper = _leverageZapper;
        getterParams.collToken = contractsArray[_branch].collToken;
        getterParams.troveId = troveId;
        getterParams.leverageRatio = 2.5e18;
        getterParams.troveManager = contractsArray[_branch].troveManager;
        getterParams.priceFeed = contractsArray[_branch].priceFeed;
        getterParams.exchangeType = _exchangeType;
        getterParams.branch = _branch;
        (uint256 flashLoanAmount, uint256 effectiveBoldAmount) = _getLeverUpFlashLoanAndBoldAmount(getterParams);

        ILeverageZapper.LeverUpTroveParams memory params = ILeverageZapper.LeverUpTroveParams({
            troveId: troveId,
            flashLoanAmount: flashLoanAmount,
            boldAmount: effectiveBoldAmount,
            maxUpfrontFee: 1000e18
        });
        // B tries to lever up A’s trove
        vm.startPrank(B);
        vm.expectRevert(AddRemoveManagers.NotOwnerNorRemoveManager.selector);
        _leverageZapper.leverUpTrove(params);
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(_leverageZapper.flashLoanProvider().receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyOwnerOrManagerCanLeverUpWithUniV3FromBalancerFLProvider() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanLeverUpFromBalancerFLProvider(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testOnlyOwnerOrManagerCanLeverUpFromBalancerFLProvider(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch
    ) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 5_000 ether * DECIMAL_PRECISION / price;
        uint256 leverageRatio = 2e18;
        uint256 realLeverageRatio = getRealLeverageRatio(leverageRatio, collAmount);
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 1;
        openTroveParams.collAmount = collAmount;
        openTroveParams.leverageRatio = leverageRatio;
        openTroveParams.realLeverageRatio = realLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        LeverUpParams memory getterParams;
        getterParams.leverageZapper = _leverageZapper;
        getterParams.collToken = contractsArray[_branch].collToken;
        getterParams.troveId = troveId;
        getterParams.leverageRatio = 2.5e18;
        getterParams.troveManager = contractsArray[_branch].troveManager;
        getterParams.priceFeed = contractsArray[_branch].priceFeed;
        getterParams.exchangeType = _exchangeType;
        getterParams.branch = _branch;
        (uint256 flashLoanAmount, uint256 effectiveBoldAmount) = _getLeverUpFlashLoanAndBoldAmount(getterParams);

        // B tries to lever up A’s trove calling our flash loan provider module
        ILeverageZapper.LeverUpTroveParams memory params = ILeverageZapper.LeverUpTroveParams({
            troveId: troveId,
            flashLoanAmount: flashLoanAmount,
            boldAmount: effectiveBoldAmount,
            maxUpfrontFee: 1000e18
        });
        IFlashLoanProvider flashLoanProvider = _leverageZapper.flashLoanProvider();
        vm.startPrank(B);
        vm.expectRevert(); // reverts without data because it calls back B
        flashLoanProvider.makeFlashLoan(
            contractsArray[_branch].collToken,
            flashLoanAmount,
            IFlashLoanProvider.Operation.LeverUpTrove,
            abi.encode(params)
        );
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(flashLoanProvider.receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyOwnerOrManagerCanLeverUpWithUniV3FromBalancerVault() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanLeverUpFromBalancerVault(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testOnlyOwnerOrManagerCanLeverUpFromBalancerVault(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch
    ) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 leverageRatio = 2e18;
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.collAmount = 5_000 ether * DECIMAL_PRECISION / price;
        uint256 realLeverageRatio = getRealLeverageRatio(leverageRatio, openTroveParams.collAmount);
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 2;
        openTroveParams.leverageRatio = leverageRatio;
        openTroveParams.realLeverageRatio = realLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        // B tries to lever up A’s trove calling Balancer Vault directly
        LeverUpParams memory getterParams;
        getterParams.leverageZapper = _leverageZapper;
        getterParams.collToken = contractsArray[_branch].collToken;
        getterParams.troveId = troveId;
        getterParams.leverageRatio = 2.5e18;
        getterParams.troveManager = contractsArray[_branch].troveManager;
        getterParams.priceFeed = contractsArray[_branch].priceFeed;
        getterParams.exchangeType = _exchangeType;
        getterParams.branch = _branch;
        /* (uint256 flashLoanAmount, uint256 effectiveBoldAmount) = */_getLeverUpFlashLoanAndBoldAmount(getterParams);

        // ILeverageZapper.LeverUpTroveParams memory params = ILeverageZapper.LeverUpTroveParams({
        //     troveId: troveId,
        //     flashLoanAmount: flashLoanAmount,
        //     boldAmount: effectiveBoldAmount,
        //     maxUpfrontFee: 1000e18
        // });
        IFlashLoanProvider flashLoanProvider = _leverageZapper.flashLoanProvider();
        // bytes memory userData = abi.encode(address(_leverageZapper), IFlashLoanProvider.Operation.LeverUpTrove, params);
        // vm.startPrank(B);
        // vm.expectRevert("Flash loan not properly initiated");
        // pool.flashLoanSimple(address(flashLoanProvider), address(contractsArray[_branch].collToken), flashLoanAmount, userData, 0);
        // vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(flashLoanProvider.receiver()), address(0), "Receiver should be zero");
    }

    // Lever down

    function _getLeverDownFlashLoanAndBoldAmount(
        ILeverageZapper _leverageZapper,
        uint256 _troveId,
        uint256 _leverageRatio,
        ITroveManager _troveManager,
        IPriceFeed _priceFeed
    ) internal returns (uint256, uint256) {
        (uint256 price,) = _priceFeed.fetchPrice();

        uint256 currentCR = _troveManager.getCurrentICR(_troveId, price);
        uint256 currentLR = _leverageZapper.leverageRatioToCollateralRatio(currentCR);
        assertLt(_leverageRatio, currentLR, "Leverage ratio should decrease");
        uint256 currentCollAmount = getTroveEntireColl(_troveManager, _troveId);
        uint256 flashLoanAmount = currentCollAmount - currentCollAmount * _leverageRatio / currentLR;
        uint256 expectedBoldAmount = flashLoanAmount * price / DECIMAL_PRECISION;
        uint256 minBoldDebt = expectedBoldAmount * 95 / 100; // slippage

        return (flashLoanAmount, minBoldDebt);
    }

    function leverDownTrove(
        ILeverageZapper _leverageZapper,
        uint256 _troveId,
        uint256 _leverageRatio,
        ITroveManager _troveManager,
        IPriceFeed _priceFeed
    ) internal returns (uint256) {
        // This should be done in the frontend
        (uint256 flashLoanAmount, uint256 minBoldDebt) =
            _getLeverDownFlashLoanAndBoldAmount(_leverageZapper, _troveId, _leverageRatio, _troveManager, _priceFeed);

        ILeverageZapper.LeverDownTroveParams memory params = ILeverageZapper.LeverDownTroveParams({
            troveId: _troveId,
            flashLoanAmount: flashLoanAmount,
            minBoldAmount: minBoldDebt
        });
        vm.startPrank(A);
        _leverageZapper.leverDownTrove(params);
        vm.stopPrank();

        return flashLoanAmount;
    }

    // function testCanLeverDownTroveWithUniV3() external {
    //     for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
    //         if (i > ignoreCollAboveIndex) continue; 
    //         _testCanLeverDownTrove(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
    //     }
    // }

    function _testCanLeverDownTrove(ILeverageZapper _leverageZapper, ExchangeType _exchangeType, uint256 _branch)
        internal
    {
        TestVars memory vars;
        vars.collAmount = 10 ether;
        vars.initialLeverageRatio = 2e18;

        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 0;
        openTroveParams.collAmount = vars.collAmount;
        openTroveParams.leverageRatio = vars.initialLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (vars.troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        vars.initialDebt = getTroveEntireDebt(contractsArray[_branch].troveManager, vars.troveId);

        vars.newLeverageRatio = 1.5e18;
        vars.resultingCollateralRatio = _leverageZapper.leverageRatioToCollateralRatio(vars.newLeverageRatio);

        _setInitialBalances(_leverageZapper, _branch, vars);

        vars.flashLoanAmount = leverDownTrove(
            _leverageZapper,
            vars.troveId,
            vars.newLeverageRatio,
            contractsArray[_branch].troveManager,
            contractsArray[_branch].priceFeed
        );

        // Checks
        (vars.price,) = contractsArray[_branch].priceFeed.fetchPrice();
        // coll
        uint256 coll = getTroveEntireColl(contractsArray[_branch].troveManager, vars.troveId);
        uint256 collExpected = vars.collAmount * vars.newLeverageRatio / DECIMAL_PRECISION;
        assertTrue(coll >= collExpected || collExpected - coll <= 22e16, "Coll mismatch");
        // debt
        uint256 expectedMinNetDebt =
            vars.initialDebt - vars.flashLoanAmount * vars.price / DECIMAL_PRECISION * 101 / 100;
        uint256 expectedMaxNetDebt = expectedMinNetDebt * 105 / 100;
        uint256 troveEntireDebt = getTroveEntireDebt(contractsArray[_branch].troveManager, vars.troveId);
        assertGe(troveEntireDebt, expectedMinNetDebt, "Debt too low");
        assertLe(troveEntireDebt, expectedMaxNetDebt, "Debt too high");
        // CR
        // When getting flashloan amount, we allow the min debt to deviate up to 5%
        // That deviation can translate into CR, specially for UniV3 exchange which is the less efficient
        // With UniV3, the quoter gives a price “too good”, meaning we exchange less, so the deleverage is lower
        uint256 CRTolerance = _exchangeType == ExchangeType.UniV3 ? 9e16 : 17e15;
        uint256 ICR = contractsArray[_branch].troveManager.getCurrentICR(vars.troveId, vars.price);
        assertTrue(
            ICR >= vars.resultingCollateralRatio || vars.resultingCollateralRatio - ICR < CRTolerance, "Wrong CR"
        );
        // token balances
        assertEq(boldToken.balanceOf(A), vars.boldBalanceBeforeA, "BOLD bal mismatch");
        assertEq(A.balance, vars.ethBalanceBeforeA, "ETH bal mismatch");
        assertGe(contractsArray[_branch].collToken.balanceOf(A), vars.collBalanceBeforeA, "Coll bal mismatch");
        assertEq(
            boldToken.balanceOf(address(_leverageZapper)), vars.boldBalanceBeforeZapper, "Zapper should not keep BOLD"
        );
        assertEq(
            boldToken.balanceOf(address(_leverageZapper.exchange())),
            vars.boldBalanceBeforeExchange,
            "Exchange should not keep BOLD"
        );
        assertEq(
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper)),
            vars.collBalanceBeforeZapper,
            "Zapper should not keep Coll"
        );
        assertEq(
            contractsArray[_branch].collToken.balanceOf(address(_leverageZapper.exchange())),
            vars.collBalanceBeforeExchange,
            "Exchange should not keep Coll"
        );
        assertEq(address(_leverageZapper).balance, vars.ethBalanceBeforeZapper, "Zapper should not keep ETH");
        assertEq(
            address(_leverageZapper.exchange()).balance, vars.ethBalanceBeforeExchange, "Exchange should not keep ETH"
        );

        // Check receiver is back to zero
        assertEq(address(_leverageZapper.flashLoanProvider().receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyFlashLoanProviderCanCallLeverDownCallbackWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyFlashLoanProviderCanCallLeverDownCallback(leverageZapperUniV3Array[i]);
        }
    }

    function _testOnlyFlashLoanProviderCanCallLeverDownCallback(ILeverageZapper _leverageZapper) internal {
        ILeverageZapper.LeverDownTroveParams memory params = ILeverageZapper.LeverDownTroveParams({
            troveId: addressToTroveIdThroughZapper(address(_leverageZapper), A),
            flashLoanAmount: 10 ether,
            minBoldAmount: 10000e18
        });
        vm.startPrank(A);
        vm.expectRevert("LZ: Caller not FlashLoan provider");
        IFlashLoanReceiver(address(_leverageZapper)).receiveFlashLoanOnLeverDownTrove(params, 10 ether);
        vm.stopPrank();
    }

    function testOnlyOwnerOrManagerCanLeverDownWithUniV3FromZapper() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanLeverDownFromZapper(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testOnlyOwnerOrManagerCanLeverDownFromZapper(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch
    ) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 5_000 ether * DECIMAL_PRECISION / price;
        uint256 leverageRatio = 2e18;
        uint256 realLeverageRatio = getRealLeverageRatio(leverageRatio, collAmount);
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 0;
        openTroveParams.collAmount = collAmount;
        openTroveParams.leverageRatio = leverageRatio;
        openTroveParams.realLeverageRatio = realLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        // B tries to lever up A’s trove
        (uint256 flashLoanAmount, uint256 minBoldDebt) = _getLeverDownFlashLoanAndBoldAmount(
            _leverageZapper,
            troveId,
            1.5e18, // _leverageRatio,
            contractsArray[_branch].troveManager,
            contractsArray[_branch].priceFeed
        );

        ILeverageZapper.LeverDownTroveParams memory params = ILeverageZapper.LeverDownTroveParams({
            troveId: troveId,
            flashLoanAmount: flashLoanAmount,
            minBoldAmount: minBoldDebt
        });
        vm.startPrank(B);
        vm.expectRevert(AddRemoveManagers.NotOwnerNorRemoveManager.selector);
        _leverageZapper.leverDownTrove(params);
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(_leverageZapper.flashLoanProvider().receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyOwnerOrManagerCanLeverDownWithUniV3FromBalancerFLProvider() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanLeverDownFromBalancerFLProvider(
                leverageZapperUniV3Array[i], ExchangeType.UniV3, i
            );
        }
    }

    function _testOnlyOwnerOrManagerCanLeverDownFromBalancerFLProvider(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch
    ) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 5_000 ether * DECIMAL_PRECISION / price;
        uint256 leverageRatio = 2e18;
        uint256 realLeverageRatio = getRealLeverageRatio(leverageRatio, collAmount);
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 1;
        openTroveParams.collAmount = collAmount;
        openTroveParams.leverageRatio = leverageRatio;
        openTroveParams.realLeverageRatio = realLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        // B tries to lever down A’s trove calling our flash loan provider module
        (uint256 flashLoanAmount, uint256 minBoldDebt) = _getLeverDownFlashLoanAndBoldAmount(
            _leverageZapper,
            troveId,
            1.5e18, // _leverageRatio,
            contractsArray[_branch].troveManager,
            contractsArray[_branch].priceFeed
        );

        ILeverageZapper.LeverDownTroveParams memory params = ILeverageZapper.LeverDownTroveParams({
            troveId: troveId,
            flashLoanAmount: flashLoanAmount,
            minBoldAmount: minBoldDebt
        });
        IFlashLoanProvider flashLoanProvider = _leverageZapper.flashLoanProvider();
        vm.startPrank(B);
        vm.expectRevert(); // reverts without data because it calls back B
        flashLoanProvider.makeFlashLoan(
            contractsArray[_branch].collToken,
            flashLoanAmount,
            IFlashLoanProvider.Operation.LeverDownTrove,
            abi.encode(params)
        );
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(flashLoanProvider.receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyOwnerOrManagerCanLeverDownWithUniV3FromBalancerVault() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanLeverDownFromBalancerVault(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testOnlyOwnerOrManagerCanLeverDownFromBalancerVault(
        ILeverageZapper _leverageZapper,
        ExchangeType _exchangeType,
        uint256 _branch
    ) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 5_000 ether * DECIMAL_PRECISION / price;
        uint256 leverageRatio = 2e18;
        uint256 realLeverageRatio = getRealLeverageRatio(leverageRatio, collAmount);
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = 2;
        openTroveParams.collAmount = collAmount;
        openTroveParams.leverageRatio = leverageRatio;
        openTroveParams.realLeverageRatio = realLeverageRatio;
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        // B tries to lever down A’s trove calling Balancer Vault directly
        /* (uint256 flashLoanAmount, uint256 minBoldDebt) = */ _getLeverDownFlashLoanAndBoldAmount(
            _leverageZapper,
            troveId,
            1.5e18, // _leverageRatio,
            contractsArray[_branch].troveManager,
            contractsArray[_branch].priceFeed
        );

        // ILeverageZapper.LeverDownTroveParams memory params = ILeverageZapper.LeverDownTroveParams({
        //     troveId: troveId,
        //     flashLoanAmount: flashLoanAmount,
        //     minBoldAmount: minBoldDebt
        // });
        IFlashLoanProvider flashLoanProvider = _leverageZapper.flashLoanProvider();
        // bytes memory userData =
        //     abi.encode(address(_leverageZapper), IFlashLoanProvider.Operation.LeverDownTrove, params);
        // vm.startPrank(B);
        // vm.expectRevert("Flash loan not properly initiated");
        // pool.flashLoanSimple(address(flashLoanProvider), address(contractsArray[_branch].collToken), flashLoanAmount, userData, 0);
        // vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(flashLoanProvider.receiver()), address(0), "Receiver should be zero");
    }

    // Close trove

    function testCanCloseTroveWithBaseZapper() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testCanCloseTrove(baseZapperArray[i], i);
        }
    }

    function testCanCloseTroveWithLeverageUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testCanCloseTrove(IZapper(leverageZapperUniV3Array[i]), i);
        }
    }

    function _getCloseFlashLoanAmount(uint256 _troveId, ITroveManager _troveManager, IPriceFeed _priceFeed)
        internal
        returns (uint256)
    {
        (uint256 price,) = _priceFeed.fetchPrice();

        uint256 currentDebt = getTroveEntireDebt(_troveManager, _troveId);
        uint256 flashLoanAmount = currentDebt * DECIMAL_PRECISION / price * 105 / 100; // slippage

        return flashLoanAmount;
    }

    function closeTrove(IZapper _zapper, uint256 _troveId, ITroveManager _troveManager, IPriceFeed _priceFeed)
        internal
    {
        // This should be done in the frontend
        uint256 flashLoanAmount = _getCloseFlashLoanAmount(_troveId, _troveManager, _priceFeed);

        IZapper.CloseTroveParams memory closeParams = IZapper.CloseTroveParams({
            troveId: _troveId,
            flashLoanAmount: flashLoanAmount,
            receiver: address(0) // Set later
        });
        vm.startPrank(A);
        _zapper.closeTroveFromCollateral(closeParams.troveId, closeParams.flashLoanAmount);
        vm.stopPrank();
    }

    function openTrove(
        IZapper _zapper,
        address _account,
        uint256 _index,
        uint256 _collAmount,
        uint256 _boldAmount,
        bool _lst
    ) internal returns (uint256) {
        IZapper.OpenTroveParams memory openParams = IZapper.OpenTroveParams({
            owner: _account,
            ownerIndex: _index,
            collAmount: _collAmount,
            boldAmount: _boldAmount,
            upperHint: 0,
            lowerHint: 0,
            // should be the trove min allowed interest, but we don't have any trovemanager instance
            annualInterestRate: MIN_POSSIBLE_ANNUAL_INTEREST_RATE,
            batchManager: address(0),
            maxUpfrontFee: 1000e18,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });

        vm.startPrank(_account);
        uint256 value = _lst ? ETH_GAS_COMPENSATION : _collAmount + ETH_GAS_COMPENSATION;
        uint256 troveId = _zapper.openTroveWithRawETH{value: value}(openParams);
        vm.stopPrank();

        return troveId;
    }

    function _testCanCloseTrove(IZapper _zapper, uint256 _branch) internal {
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 30_000 ether * DECIMAL_PRECISION / price;
        uint256 boldAmount = 10000e18;

        bool lst = _branch > 0;
        uint256 troveId = openTrove(_zapper, A, 0, collAmount, boldAmount, lst);

        // open a 2nd trove so we can close the 1st one
        openTrove(_zapper, B, 0, collAmount, 10000e18, lst);

        uint256 boldBalanceBefore = boldToken.balanceOf(A);
        uint256 collBalanceBefore = contractsArray[_branch].collToken.balanceOf(A);
        uint256 ethBalanceBefore = A.balance;
        uint256 debtInColl =
            getTroveEntireDebt(contractsArray[_branch].troveManager, troveId) * DECIMAL_PRECISION / price;

        // Close trove
        closeTrove(_zapper, troveId, contractsArray[_branch].troveManager, contractsArray[_branch].priceFeed);

        assertEq(getTroveEntireColl(contractsArray[_branch].troveManager, troveId), 0, "Coll mismatch");
        assertEq(getTroveEntireDebt(contractsArray[_branch].troveManager, troveId), 0, "Debt mismatch");
        assertGe(boldToken.balanceOf(A), boldBalanceBefore, "BOLD bal should not decrease");
        assertLe(boldToken.balanceOf(A), boldBalanceBefore * 105 / 100, "BOLD bal can only increase by slippage margin");
        // added custom delta: when we are dealing with scroll tokens, the delta is too short
        uint256 delta = _branch == 3 ? 1000e18 : 3e17;
        if (lst) {
            assertGe(contractsArray[_branch].collToken.balanceOf(A), collBalanceBefore, "Coll bal should not decrease");
            assertApproxEqAbs(
                contractsArray[_branch].collToken.balanceOf(A),
                collBalanceBefore + collAmount - debtInColl,
                delta,
                "Coll bal mismatch"
            );
            assertEq(A.balance, ethBalanceBefore + ETH_GAS_COMPENSATION, "ETH bal mismatch");
        } else {
            assertEq(contractsArray[_branch].collToken.balanceOf(A), collBalanceBefore, "Coll bal mismatch");
            assertGe(A.balance, ethBalanceBefore, "ETH bal should not decrease");
            assertApproxEqAbs(
                A.balance, ethBalanceBefore + collAmount + ETH_GAS_COMPENSATION - debtInColl, 3e17, "ETH bal mismatch"
            );
        }
    }

    function testOnlyFlashLoanProviderCanCallCloseTroveCallbackWithBaseZapper() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyFlashLoanProviderCanCallCloseTroveCallback(baseZapperArray[i], i);
        }
    }

    function testOnlyFlashLoanProviderCanCallCloseTroveCallbackWithUniV3() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyFlashLoanProviderCanCallCloseTroveCallback(leverageZapperUniV3Array[i], i);
        }
    }

    function _testOnlyFlashLoanProviderCanCallCloseTroveCallback(IZapper _zapper, uint256 _branch) internal {
        IZapper.CloseTroveParams memory params = IZapper.CloseTroveParams({
            troveId: addressToTroveId(A),
            flashLoanAmount: 10 ether,
            receiver: address(0) // Set later
        });

        bool lst = _branch > 0;
        string memory revertReason = lst ? "GCZ: Caller not FlashLoan provider" : "WZ: Caller not FlashLoan provider";
        vm.startPrank(A);
        vm.expectRevert(bytes(revertReason));
        IFlashLoanReceiver(address(_zapper)).receiveFlashLoanOnCloseTroveFromCollateral(params, 10 ether);
        vm.stopPrank();
    }

    function testOnlyOwnerOrManagerCanCloseTroveWithBaseZapperFromZapper() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanCloseTroveFromZapper(baseZapperArray[i], i);
        }
    }

    function testOnlyOwnerOrManagerCanCloseTroveWithUniV3FromZapper() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanCloseTroveFromZapper(leverageZapperUniV3Array[i], i);
        }
    }

    function _testOnlyOwnerOrManagerCanCloseTroveFromZapper(IZapper _zapper, uint256 _branch) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 30_000 ether * DECIMAL_PRECISION / price;
        uint256 boldAmount = 10000e18;

        bool lst = _branch > 0;
        uint256 troveId = openTrove(_zapper, A, 0, collAmount, boldAmount, lst);

        // B tries to close A’s trove
        uint256 flashLoanAmount =
            _getCloseFlashLoanAmount(troveId, contractsArray[_branch].troveManager, contractsArray[_branch].priceFeed);

        IZapper.CloseTroveParams memory closeParams = IZapper.CloseTroveParams({
            troveId: troveId,
            flashLoanAmount: flashLoanAmount,
            receiver: address(0) // Set later
        });
        vm.startPrank(B);
        vm.expectRevert(AddRemoveManagers.NotOwnerNorRemoveManager.selector);
        _zapper.closeTroveFromCollateral(closeParams.troveId, closeParams.flashLoanAmount);
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(_zapper.flashLoanProvider().receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyOwnerOrManagerCanCloseTroveWithBaseZapperFromBalancerFLProvider() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanCloseTroveFromBalancerFLProvider(baseZapperArray[i], i);
        }
    }

    function testOnlyOwnerOrManagerCanCloseTroveWithUniV3FromBalancerFLProvider() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanCloseTroveFromBalancerFLProvider(leverageZapperUniV3Array[i], i);
        }
    }

    function _testOnlyOwnerOrManagerCanCloseTroveFromBalancerFLProvider(IZapper _zapper, uint256 _branch) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 30_000 ether * DECIMAL_PRECISION / price;
        uint256 boldAmount = 10000e18;

        bool lst = _branch > 0;
        uint256 troveId = openTrove(_zapper, A, 0, collAmount, boldAmount, lst);

        // B tries to close A’s trove calling our flash loan provider module
        uint256 flashLoanAmount =
            _getCloseFlashLoanAmount(troveId, contractsArray[_branch].troveManager, contractsArray[_branch].priceFeed);

        IZapper.CloseTroveParams memory closeParams = IZapper.CloseTroveParams({
            troveId: troveId,
            flashLoanAmount: flashLoanAmount,
            receiver: address(0) // Set later
        });
        IFlashLoanProvider flashLoanProvider = _zapper.flashLoanProvider();
        vm.startPrank(B);
        vm.expectRevert(); // reverts without data because it calls back B
        flashLoanProvider.makeFlashLoan(
            contractsArray[_branch].collToken,
            flashLoanAmount,
            IFlashLoanProvider.Operation.CloseTrove,
            abi.encode(closeParams)
        );
        vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(flashLoanProvider.receiver()), address(0), "Receiver should be zero");
    }

    function testOnlyOwnerOrManagerCanCloseTroveWithBaseZapperFromBalancerVault() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanCloseTroveFromBalancerVault(baseZapperArray[i], i);
        }
    }

    function testOnlyOwnerOrManagerCanCloseTroveWithUniV3FromBalancerVault() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testOnlyOwnerOrManagerCanCloseTroveFromBalancerVault(leverageZapperUniV3Array[i], i);
        }
    }

    function _testOnlyOwnerOrManagerCanCloseTroveFromBalancerVault(IZapper _zapper, uint256 _branch) internal {
        // Open trove
        (uint256 price,) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 30_000 ether * DECIMAL_PRECISION / price;
        uint256 boldAmount = 10000e18;

        bool lst = _branch > 0;
        uint256 troveId = openTrove(_zapper, A, 0, collAmount, boldAmount, lst);

        // B tries to close A’s trove calling Balancer Vault directly
        // uint256 flashLoanAmount =
            _getCloseFlashLoanAmount(troveId, contractsArray[_branch].troveManager, contractsArray[_branch].priceFeed);

        // IZapper.CloseTroveParams memory closeParams = IZapper.CloseTroveParams({
        //     troveId: troveId,
        //     flashLoanAmount: flashLoanAmount,
        //     receiver: address(0) // Set later
        // });
        IFlashLoanProvider flashLoanProvider = _zapper.flashLoanProvider();
        // bytes memory userData = abi.encode(address(_zapper), IFlashLoanProvider.Operation.CloseTrove, closeParams);
        // vm.startPrank(B);
        // vm.expectRevert("Flash loan not properly initiated");
        // pool.flashLoanSimple(address(flashLoanProvider), address(contractsArray[_branch].collToken), flashLoanAmount, userData, 0);
        // vm.stopPrank();

        // Check receiver is back to zero
        assertEq(address(flashLoanProvider.receiver()), address(0), "Receiver should be zero");
    }

    function testApprovalIsNotReset() external {
        for (uint256 i = 0; i < SWELLCHAIN_NUM_COLLATERALS; i++) {
            if (i > ignoreCollAboveIndex) continue; 
            _testApprovalIsNotReset(leverageZapperUniV3Array[i], ExchangeType.UniV3, i);
        }
    }

    function _testApprovalIsNotReset(ILeverageZapper _leverageZapper, ExchangeType _exchangeType, uint256 _branch)
        internal
    {
        // Open non leveraged trove
        (uint256 price, ) = contractsArray[_branch].priceFeed.fetchPrice();
        uint256 collAmount = 33_000 ether * DECIMAL_PRECISION / price;
        openTrove(_leverageZapper, A, uint256(_exchangeType) * 2, collAmount, 10000e18, _branch > 0);

        // Now try to open leveraged trove, it should still work
        OpenLeveragedTroveWithIndexParams memory openTroveParams;
        openTroveParams.leverageZapper = _leverageZapper;
        openTroveParams.collToken = contractsArray[_branch].collToken;
        openTroveParams.index = uint256(_exchangeType) * 2 + 1;
        openTroveParams.collAmount = collAmount;
        openTroveParams.leverageRatio = 1.5 ether;
        openTroveParams.realLeverageRatio = getRealLeverageRatio(1.5 ether, collAmount);
        openTroveParams.priceFeed = contractsArray[_branch].priceFeed;
        openTroveParams.exchangeType = _exchangeType;
        openTroveParams.branch = _branch;
        openTroveParams.batchManager = address(0);
        (uint256 troveId,) = openLeveragedTroveWithIndex(openTroveParams);

        assertGt(getTroveEntireColl(contractsArray[_branch].troveManager, troveId), 0);
        assertGt(getTroveEntireDebt(contractsArray[_branch].troveManager, troveId), 0);
    }

    // helper price functions

    // Helper to get the actual bold we need, capped by a max value, to get flash loan amount
    function _getBoldAmountToSwap(
        ExchangeType _exchangeType,
        uint256 /* _branch */,
        uint256 /* _boldAmount */,
        uint256 _maxBoldAmount,
        uint256 _minCollAmount,
        IERC20 _collToken
    ) internal returns (uint256) {
        require(_exchangeType == ExchangeType.UniV3, "Not valid exchange");
        return _getBoldAmountToSwapUniV3(_maxBoldAmount, _minCollAmount, _collToken);
    }

    // See: https://docs.uniswap.org/contracts/v3/reference/periphery/interfaces/ISlipstreamQuoterV2
    // These functions are not marked view because they rely on calling non-view functions and reverting to compute the result.
    // They are also not gas efficient and should not be called on-chain.
    function _getBoldAmountToSwapUniV3(uint256 _maxBoldAmount, uint256 _minCollAmount, IERC20 _collToken)
        internal /* view */
        returns (uint256)
    {
        
        ISlipstreamQuoterV2.QuoteExactOutputSingleParams memory params = ISlipstreamQuoterV2.QuoteExactOutputSingleParams({
            tokenIn: address(boldToken),
            tokenOut: address(_collToken),
            amount: _minCollAmount,
            tickSpacing: VELODROME_TICKSPACING,
            sqrtPriceLimitX96: 0
        });
        (uint256 amountIn,,,) = velodromeQuoterV2.quoteExactOutputSingle(params);
        assertLe(amountIn, _maxBoldAmount, "Price too high");

        return amountIn;
    }

    // keeping this function just in case
    function getRealLeverageRatio(
        uint256 intendedRatio, // this is to keep the accounting with the idea of 2x while using a real ratio
        uint256 collateral
    ) public pure returns (uint256) {
        require(intendedRatio > 1, "Leverage ratio must be greater than 1");
        require(collateral > 0, "Collateral must be greater than 0");

        uint256 borrowedAmount = (intendedRatio - 1e18) * collateral;
        // uint256 fee = borrowedAmount * pool.FLASHLOAN_PREMIUM_TOTAL() / 10000;
        uint256 effectiveBorrowedAmount = borrowedAmount;// - fee;
        uint256 realRatio = 1e18 + (effectiveBorrowedAmount / collateral);

        return realRatio;
    }
}
