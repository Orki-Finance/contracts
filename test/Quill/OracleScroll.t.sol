// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../OracleMainnet.t.sol";

import "./TestContracts/QuillDeployment.t.sol";

contract OracleScroll is TestAccounts {
    AggregatorV3Interface ethOracle;
    AggregatorV3Interface wstethOracle;
    AggregatorV3Interface weethOracle;
    AggregatorV3Interface scrollOracle;

    ChainlinkOracleMock mockOracle;

    IERC20 weth;
    IERC20 wsteth;
    IERC20 weeth;
    IERC20 scroll;

    TestDeployer.LiquityContracts[] contractsArray;
    ICollateralRegistry collateralRegistry;
    IBoldToken quill;

    IPriceFeed wethPriceFeed;
    IPriceFeed wstethPriceFeed;
    IPriceFeed weethPriceFeed;
    IPriceFeed scrollPriceFeed;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("scroll"));
        vm.rollFork(10606979);

        accounts = new Accounts();
        createAccounts();

        (A, B, C, D, E, F) =
            (accountsList[0], accountsList[1], accountsList[2], accountsList[3], accountsList[4], accountsList[5]);

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
        collateralRegistry = result.collateralRegistry;
        quill = result.quillToken;

        ethOracle = AggregatorV3Interface(result.externalAddresses.ETH_USD_Oracle);
        wstethOracle = AggregatorV3Interface(result.externalAddresses.WSTETH_STETH_Oracle);
        weethOracle = AggregatorV3Interface(result.externalAddresses.WEETH_ETH_Oracle);
        scrollOracle = AggregatorV3Interface(result.externalAddresses.SCROLL_USD_Oracle);

        mockOracle = new ChainlinkOracleMock();

        weth = IERC20(result.externalAddresses.WETH_Token);
        wsteth = IERC20(result.externalAddresses.WSTETH_Token);
        weeth = IERC20(result.externalAddresses.WEETH_Token);

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

            vm.startPrank(accountsList[i]);
        }

        wethPriceFeed = IPriceFeed(address(contractsArray[0].priceFeed));
        wstethPriceFeed = IPriceFeed(address(contractsArray[1].priceFeed));
        weethPriceFeed = IPriceFeed(address(contractsArray[2].priceFeed));
        scrollPriceFeed = IPriceFeed(address(contractsArray[3].priceFeed));
    }

    function testAllPrices() public view {
        console.log("WETH  ", wethPriceFeed.lastGoodPrice());
        console.log("WSTETH", wstethPriceFeed.lastGoodPrice());
        console.log("WEETH ", weethPriceFeed.lastGoodPrice());
        console.log("SCROLL    ", scrollPriceFeed.lastGoodPrice());
    }

    function _getLatestAnswerFromOracle(AggregatorV3Interface _oracle) internal view returns (uint256) {
        (, int256 answer,,,) = _oracle.latestRoundData();

        uint256 decimals = _oracle.decimals();
        assertLe(decimals, 18);
        // Convert to uint and scale up to 18 decimals
        return uint256(answer) * 10 ** (18 - decimals);
    }

    function testSetLastGoodPriceOnDeploymentWETH() public view {
        uint256 lastGoodPriceWeth = wethPriceFeed.lastGoodPrice();
        assertGt(lastGoodPriceWeth, 0);

        uint256 latestAnswerEthUsd = _getLatestAnswerFromOracle(ethOracle);

        assertEq(lastGoodPriceWeth, latestAnswerEthUsd);
    }

    function testSetLastGoodPriceOnDeploymentWSTETH() public view {
        uint256 usdPrice = wstethPriceFeed.lastGoodPrice();
        assertGt(usdPrice, 0);

        uint256 answerWsteth = _getLatestAnswerFromOracle(wstethOracle);
        uint256 answerEth = _getLatestAnswerFromOracle(ethOracle);

        uint256 expectedPrice = (answerWsteth * answerEth) / 1e18;

        assertEq(usdPrice, expectedPrice);
    }

    function testSetLastGoodPriceOnDeploymentWEETH() public view {
        uint256 usdPrice = weethPriceFeed.lastGoodPrice();
        assertGt(usdPrice, 0);

        uint256 answerWeeth = _getLatestAnswerFromOracle(weethOracle);
        uint256 answerEthUsd = _getLatestAnswerFromOracle(ethOracle);

        uint256 expectedPrice = (answerWeeth * answerEthUsd) / 1e18;

        assertEq(usdPrice, expectedPrice);
    }

    function testSetLastGoodPriceOnDeploymentSCROLL() public view {
        uint256 usdPrice = scrollPriceFeed.lastGoodPrice();
        assertGt(usdPrice, 0);

        uint256 expectedPrice = _getLatestAnswerFromOracle(scrollOracle);

        assertEq(usdPrice, expectedPrice);
    }
}
