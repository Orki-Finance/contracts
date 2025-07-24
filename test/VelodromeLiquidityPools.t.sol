// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BoldToken} from "src/BoldToken.sol";
import {IRouter} from "src/Zappers/Modules/Exchanges/Velodrome/IRouter.sol";
import {DECIMAL_PRECISION} from "src/Dependencies/Constants.sol";
import {IPoolFactory} from "src/Zappers/Modules/Exchanges/Velodrome/IPoolFactory.sol";
import {ICLFactory} from "src/Zappers/Modules/Exchanges/Slipstream/core/ICLFactory.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISlipstreamNonfungiblePositionManager} from "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamNonfungiblePositionManager.sol";
import {
    initVelodromeLiquidityPool,
    InitVelodromeLiquidityPoolArgs,
    initSlipstreamLiquidityPool,
    InitSlipstreamLiquidityPoolArgs
} from "script/VelodromeLiquidityPools.s.sol";

contract VelodromeLiquidityPoolsTest is Test {
    address user = address(this);

    uint256 constant USDC_1 = 1e6;
    uint256 constant TOKEN_1 = 1e18;

    uint256 constant USDC_PRECISION = 10 ** 6;

    IERC20 BOLD;
    IERC20 USDC = IERC20(0x99a38322cAF878Ef55AE4d0Eda535535eF8C7960);

    IRouter velodromeRouter = IRouter(0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45);
    IPoolFactory velodromePoolFactory = IPoolFactory(0x31832f2a97Fd20664D76Cc421207669b55CE4BC0);

    ICLFactory slipstreamPoolFactory = ICLFactory(0x04625B046C69577EfC40e6c0Bb83CDBAfab5a55F);
    ISlipstreamNonfungiblePositionManager slipstreamPositionManager =
        ISlipstreamNonfungiblePositionManager(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("swellchain"));
        BOLD = new BoldToken{salt: keccak256(abi.encodePacked(block.timestamp))}();
    }

    function test_initVelodromeLiquidityPool() public {
        deal(address(BOLD), user, TOKEN_1);
        uint256 initialTokenABalance = BOLD.balanceOf(user);
        assertEq(initialTokenABalance, TOKEN_1);

        deal(address(USDC), user, USDC_1);
        uint256 initialTokenBBalance = USDC.balanceOf(user);
        assertEq(initialTokenBBalance, USDC_1);

        InitVelodromeLiquidityPoolArgs memory args;
        args.deployer = user;
        args.router = velodromeRouter;
        args.tokenA = BOLD;
        args.tokenB = USDC;
        args.stable = true;
        args.amountADesired = TOKEN_1;
        args.amountBDesired = USDC_1;

        address poolNormal = velodromeRouter.poolFor(address(args.tokenA), address(args.tokenB), args.stable);
        address poolReverse = velodromeRouter.poolFor(address(args.tokenB), address(args.tokenA), args.stable);

        assertFalse(velodromePoolFactory.isPool(poolNormal));
        assertFalse(velodromePoolFactory.isPool(poolReverse));

        (uint256 amountA, uint256 amountB,) = initVelodromeLiquidityPool(args);
        assertEq(amountA, TOKEN_1);
        assertEq(amountB, USDC_1);

        assertTrue(velodromePoolFactory.isPool(poolNormal));
        assertTrue(velodromePoolFactory.isPool(poolReverse));

        assertEq(BOLD.balanceOf(poolNormal), amountA);
        assertEq(USDC.balanceOf(poolNormal), amountB);
        assertEq(BOLD.balanceOf(poolNormal), TOKEN_1);
        assertEq(USDC.balanceOf(poolNormal), USDC_1);

        assertEq(BOLD.balanceOf(poolReverse), amountA);
        assertEq(USDC.balanceOf(poolReverse), amountB);
        assertEq(BOLD.balanceOf(poolReverse), TOKEN_1);
        assertEq(USDC.balanceOf(poolReverse), USDC_1);

        assertEq(BOLD.balanceOf(user), initialTokenABalance - amountA);
        assertEq(USDC.balanceOf(user), initialTokenBBalance - amountB);
        assertEq(BOLD.balanceOf(user), 0);
        assertEq(USDC.balanceOf(user), 0);
    }

    function test_initSlipstreamLiquidityPool() public {
        deal(address(BOLD), user, TOKEN_1);
        uint256 initialBoldBalance = BOLD.balanceOf(user);
        assertEq(initialBoldBalance, TOKEN_1);

        deal(address(USDC), user, USDC_1);
        uint256 initialUsdcBalance = USDC.balanceOf(user);
        assertEq(initialUsdcBalance, USDC_1);

        uint256 upscaledPrice = DECIMAL_PRECISION * USDC_PRECISION / DECIMAL_PRECISION;

        InitSlipstreamLiquidityPoolArgs memory args;
        args.deployer = user;
        args.poolFactory = slipstreamPoolFactory;
        args.positionManager = slipstreamPositionManager;
        args.tokenA = USDC;
        args.tokenB = BOLD;
        args.amountADesired = USDC_1;
        args.amountBDesired = TOKEN_1;
        args.tickSpacing = 200;
        args.upscaledPrice = upscaledPrice;

        (address poolAddress, uint256 tokenA, uint256 tokenB) = initSlipstreamLiquidityPool(args);
        (uint256 usdcAmount, uint256 boldAmount) = address(USDC) < address(BOLD) ? (tokenA, tokenB) : (tokenB, tokenA);

        assertEq(BOLD.balanceOf(poolAddress), boldAmount);
        assertEq(USDC.balanceOf(poolAddress), usdcAmount);

        assertEq(BOLD.balanceOf(user), initialBoldBalance - boldAmount);
        assertEq(USDC.balanceOf(user), initialUsdcBalance - usdcAmount);
    }

    function test_initSlipstreamLiquidityPool_inverseInputOrder() public {
        deal(address(BOLD), user, TOKEN_1);
        uint256 initialBoldBalance = BOLD.balanceOf(user);
        assertEq(initialBoldBalance, TOKEN_1);

        deal(address(USDC), user, USDC_1);
        uint256 initialUsdcBalance = USDC.balanceOf(user);
        assertEq(initialUsdcBalance, USDC_1);

        uint256 price = DECIMAL_PRECISION / USDC_PRECISION;
        uint256 upscaledPrice = price * DECIMAL_PRECISION;

        InitSlipstreamLiquidityPoolArgs memory args;
        args.deployer = user;
        args.poolFactory = slipstreamPoolFactory;
        args.positionManager = slipstreamPositionManager;
        args.tokenA = BOLD;
        args.tokenB = USDC;
        args.amountADesired = TOKEN_1;
        args.amountBDesired = USDC_1;
        args.tickSpacing = 200;
        args.upscaledPrice = upscaledPrice;

        (address poolAddress, uint256 tokenA, uint256 tokenB) = initSlipstreamLiquidityPool(args);
        (uint256 usdcAmount, uint256 boldAmount) = address(USDC) < address(BOLD) ? (tokenA, tokenB) : (tokenB, tokenA);

        assertEq(BOLD.balanceOf(poolAddress), boldAmount);
        assertEq(USDC.balanceOf(poolAddress), usdcAmount);

        assertEq(BOLD.balanceOf(user), initialBoldBalance - boldAmount);
        assertEq(USDC.balanceOf(user), initialUsdcBalance - usdcAmount);
    }
}
