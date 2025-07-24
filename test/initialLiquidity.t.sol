// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./OracleMainnet.t.sol";
import "./Quill/TestContracts/QuillDeployment.t.sol";
import "../script/InitialLiquidityHelpers.s.sol";
import {ICrocSwapQuery} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapQuery.sol";

contract InitialLiquidityTests is TestAccounts {
    IBoldToken quill;
    IHintHelpers hintHelpers;
    TestDeployer.LiquityContracts[] contractsArray;

    IERC20Metadata USDC = IERC20Metadata(0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4);
    uint256 USDC_PRECISION = 10 ** 6;

    uint24 constant UNIV3_FEE = 0.3e4;
    INonfungiblePositionManager constant scrollUniV3PositionManager =
        INonfungiblePositionManager(0xB39002E4033b162fAc607fc3471E205FA2aE5967);

    ICrocSwapDex crocSwapDex = ICrocSwapDex(0xaaaaAAAACB71BF2C8CaE522EA5fa455571A74106);
    ICrocSwapQuery crocSwapQuery = ICrocSwapQuery(0x62223e90605845Cf5CC6DAE6E0de4CDA130d6DDf);

    function setUp() private {
        vm.createSelectFork(vm.rpcUrl("scroll"));

        accounts = new Accounts();
        createAccounts();

        A = accountsList[0];

        uint256 numCollaterals = 4;
        TestDeployer.TroveManagerParams memory tmParams =
            TestDeployer.TroveManagerParams(150e16, 110e16, 110e16, 10e16, 5e16, 10e16, 500e18, 72e16, _1pct / 2);
        TestDeployer.TroveManagerParams[] memory troveManagerParamsArray =
            new QuillTestDeployer.TroveManagerParams[](numCollaterals);
        for (uint256 i = 0; i < troveManagerParamsArray.length; i++) {
            troveManagerParamsArray[i] = tmParams;
        }

        QuillTestDeployer deployer = new QuillTestDeployer();
        QuillTestDeployer.DeploymentResultQuill memory result =
            deployer.deployAndConnectContractsQuill(troveManagerParamsArray);
        hintHelpers = result.hintHelpers;
        quill = result.quillToken;

        // Record contracts
        for (uint256 c = 0; c < numCollaterals; c++) {
            contractsArray.push(result.contractsArray[c]);
        }

        // Give all users all collaterals
        uint256 initialColl = 1000_000e18;
        for (uint256 i = 0; i < 6; i++) {
            for (uint256 j = 0; j < numCollaterals; j++) {
                deal(address(contractsArray[j].collToken), accountsList[i], initialColl);
                vm.startPrank(accountsList[i]);
                // Approve all Borrower Ops to use the user's WETH funds
                contractsArray[0].collToken.approve(address(contractsArray[j].borrowerOperations), type(uint256).max);
                // Approve Borrower Ops in LST branches to use the user's respective LST funds
                contractsArray[j].collToken.approve(address(contractsArray[j].borrowerOperations), type(uint256).max);
                vm.stopPrank();
            }
        }
    }

    function test_openInitialLiquidityTrove() private {
        uint256 interestRate = _1pct / 2;
        uint256 upfrontFee = hintHelpers.predictOpenTroveUpfrontFee(0, 500e18, interestRate);
        uint256 expectedQuillBalance = 500e18;

        assertEq(quill.balanceOf(A), 0);

        vm.startPrank(A);
        openInitialLiquidityTrove(A, contractsArray[0].borrowerOperations, 500e18, 500e18, interestRate, upfrontFee);
        vm.stopPrank();

        assertEq(quill.balanceOf(A), expectedQuillBalance);
    }

    function test_provideUniV3Liquidity_WETH() private {
        IERC20Metadata collToken = contractsArray[0].addressesRegistry.collToken(); // WETH

        uint256 interestRate = _1pct / 2;
        uint256 upfrontFee = hintHelpers.predictOpenTroveUpfrontFee(0, 1000e18, interestRate);

        vm.startPrank(A);
        openInitialLiquidityTrove(A, contractsArray[0].borrowerOperations, 1000e18, 1000e18, interestRate, upfrontFee);

        uint256 initialQuillBalance = quill.balanceOf(A);
        uint256 initialCollBalance = collToken.balanceOf(A);

        (uint256 price,) = contractsArray[0].priceFeed.fetchPrice();

        // amount0 == collateral && amount1 == quill
        (address uniV3PoolAddress, uint256 amount0, uint256 amount1) = provideUniV3Liquidity(
            A,
            scrollUniV3PositionManager,
            quill,
            collToken,
            1000e18,
            1000e18 * DECIMAL_PRECISION / price,
            price,
            UNIV3_FEE
        );
        vm.stopPrank();

        assertEq(quill.balanceOf(uniV3PoolAddress), amount1);
        assertEq(quill.balanceOf(A), initialQuillBalance - amount1);

        assertEq(collToken.balanceOf(uniV3PoolAddress), amount0);
        assertEq(collToken.balanceOf(A), initialCollBalance - amount0);

        assertGt(amount1, 975e18);
        assertLt(amount1, 1001e18);

        assertGt(amount0, 975e18 * DECIMAL_PRECISION / price);
        assertLt(amount0, 1001e18 * DECIMAL_PRECISION / price);
    }

    function test_provideUniV3Liquidity_USDC() private {
        deal(address(USDC), A, 1000e6);

        uint256 interestRate = _1pct / 2;
        uint256 upfrontFee = hintHelpers.predictOpenTroveUpfrontFee(0, 1000e18, interestRate);

        vm.startPrank(A);
        openInitialLiquidityTrove(A, contractsArray[0].borrowerOperations, 1000e18, 1000e18, interestRate, upfrontFee);

        uint256 initialQuillBalance = quill.balanceOf(A);
        uint256 initialUSDCBalance = USDC.balanceOf(A);

        uint256 price = DECIMAL_PRECISION / USDC_PRECISION;
        uint256 upscaled_price = price * DECIMAL_PRECISION;

        // amount0 == USDC && amount1 == quill
        (address uniV3PoolAddress, uint256 amount0, uint256 amount1) = provideUniV3Liquidity(
            A, scrollUniV3PositionManager, quill, USDC, 1000e18, 1000e6, upscaled_price, UNIV3_FEE
        );
        vm.stopPrank();

        assertEq(quill.balanceOf(uniV3PoolAddress), amount1);
        assertEq(quill.balanceOf(A), initialQuillBalance - amount1);

        assertEq(USDC.balanceOf(uniV3PoolAddress), amount0);
        assertEq(USDC.balanceOf(A), initialUSDCBalance - amount0);

        assertGt(amount0, 975e6);
        assertLt(amount0, 1001e6);

        assertGt(amount1, 975e18);
        assertLt(amount1, 1001e18);
    }

    function test_initCrocSwapLP_USDC() private {
        deal(address(USDC), A, 1e6); //1 $ should be more than enough since decimals are way greater on usdq 
        (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(address(USDC), address(quill));

        uint256 interestRate = _1pct / 2;
        uint256 upfrontFee = hintHelpers.predictOpenTroveUpfrontFee(0, 1000e18, interestRate);

        vm.startPrank(A);
        openInitialLiquidityTrove(A, contractsArray[0].borrowerOperations, 1000e18, 1000e18, interestRate, upfrontFee);
        USDC.approve(address(crocSwapDex), 1e6); // 1$
        quill.approve(address(crocSwapDex), 1e18); // 1$

        initCrocSwapPool(crocSwapDex, quill, USDC, DECIMAL_PRECISION); // 1 usdq / usdc, since we assume oracle prices with 18 decimals, 1e18
        vm.stopPrank();

        uint128 newPriceRoot = crocSwapQuery.queryCurve(base, quote, CrocSwapDexHelper.POOL_TYPE_INDEX).priceRoot_;

        uint256 priceInUSDQ = CrocSwapDexHelper.priceInUSDq(newPriceRoot, address(quill), address(USDC), quill.decimals(), USDC.decimals());
        assertApproxEqRel(priceInUSDQ, DECIMAL_PRECISION, 1e16); //less than 1% delta
    }

    function test_initCrocSwapLP_COLLS() private {
        uint256 interestRate = _1pct / 2;
        uint256 upfrontFee = hintHelpers.predictOpenTroveUpfrontFee(0, 1000e18, interestRate);

        vm.prank(A);
        openInitialLiquidityTrove(A, contractsArray[0].borrowerOperations, 1000e18, 1000e18, interestRate, upfrontFee);

        for(uint collIndex = 0; collIndex < 4; collIndex++){
            (uint256 price,) = contractsArray[collIndex].priceFeed.fetchPrice();
            IERC20Metadata COLL = contractsArray[collIndex].collToken;
            (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(address(COLL), address(quill));
            vm.startPrank(A);
            if(collIndex != 3){
                COLL.approve(address(crocSwapDex), 2e15); // 0.002 eth ~ 1$
            } else {
                //$scr
                COLL.approve(address(crocSwapDex), 1e18); // 1 scr ~ 1$
            }
            quill.approve(address(crocSwapDex), 1e18); // 1$

            initCrocSwapPool(crocSwapDex, quill, COLL, price); // 1 usdq / usdc, since we assume oracle prices with 18 decimals, 1e18
            vm.stopPrank();

            uint128 newPriceRoot = crocSwapQuery.queryCurve(base, quote, CrocSwapDexHelper.POOL_TYPE_INDEX).priceRoot_;

            uint256 priceInUSDQ = CrocSwapDexHelper.priceInUSDq(newPriceRoot, address(quill), address(COLL), quill.decimals(), COLL.decimals());
            assertApproxEqRel(priceInUSDQ, price, 1e16); //less than 1% delta
        }
    }

    function test_initCrocSwapLP_ETH() private {
        deal(A, 1000); //1000 wei should be more than enough 
        (uint256 price,) = contractsArray[0].priceFeed.fetchPrice();
        address ETH_VIRT_ADDR = address(0x0);
        (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(ETH_VIRT_ADDR, address(quill));
        uint256 interestRate = _1pct / 2;
        uint256 upfrontFee = hintHelpers.predictOpenTroveUpfrontFee(0, 1000e18, interestRate);

        vm.startPrank(A);
        openInitialLiquidityTrove(A, contractsArray[0].borrowerOperations, 1000e18, 1000e18, interestRate, upfrontFee);
        quill.approve(address(crocSwapDex), 1e18); // 1$

        initCrocSwapETHPool(crocSwapDex, quill, price);
        vm.stopPrank();

        uint128 newPriceRoot = crocSwapQuery.queryCurve(base, quote, CrocSwapDexHelper.POOL_TYPE_INDEX).priceRoot_;

        uint256 priceInUSDQ = CrocSwapDexHelper.priceInUSDq(newPriceRoot, address(quill), ETH_VIRT_ADDR, quill.decimals(), 18);
        assertApproxEqRel(priceInUSDQ, price, 1e16); //less than 1% delta
    }
}
