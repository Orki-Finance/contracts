// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {DECIMAL_PRECISION} from "src/Dependencies/Constants.sol";

import {IRouter} from "src/Zappers/Modules/Exchanges/Velodrome/IRouter.sol";
import {ICLPool} from "src/Zappers/Modules/Exchanges/Slipstream/core/ICLPool.sol";
import {ICLFactory} from "src/Zappers/Modules/Exchanges/Slipstream/core/ICLFactory.sol";
import {ISlipstreamNonfungiblePositionManager} from "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamNonfungiblePositionManager.sol";

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

struct InitVelodromeLiquidityPoolArgs {
    address deployer;
    IRouter router;
    IERC20 tokenA;
    IERC20 tokenB;
    bool stable;
    uint256 amountADesired;
    uint256 amountBDesired;
}

function initVelodromeLiquidityPool(InitVelodromeLiquidityPoolArgs memory args)
    returns (uint256 amountA, uint256 amountB, uint256 liquidity)
{
    args.tokenA.approve(address(args.router), args.amountADesired);
    args.tokenB.approve(address(args.router), args.amountBDesired);

    (amountA, amountB, liquidity) = args.router.addLiquidity(
        address(args.tokenA),
        address(args.tokenB),
        args.stable,
        args.amountADesired,
        args.amountBDesired,
        args.amountADesired,
        args.amountBDesired,
        args.deployer,
        block.timestamp + 10 minutes
    );
}

struct InitSlipstreamLiquidityPoolArgs {
    address deployer;
    ICLFactory poolFactory;
    ISlipstreamNonfungiblePositionManager positionManager;
    IERC20 tokenA;
    IERC20 tokenB;
    uint256 amountADesired;
    uint256 amountBDesired;
    int24 tickSpacing;
    uint256 upscaledPrice; // price * DECIMAL_PRECISION
}

struct InitSlipstreamLiquidityPoolVars {
    int24 TICK_SPACING;
    int24 tick;
    int24 tickLower;
    int24 tickUpper;
    address[2] tokens;
    uint256[2] amounts;
    uint256 price;
    uint160 sqrtPriceX96;
}

function initSlipstreamLiquidityPoolJump(InitSlipstreamLiquidityPoolArgs memory args)
    returns (address pool, uint256 amountA, uint256 amountB)
{
    InitSlipstreamLiquidityPoolVars memory vars;

    args.tokenA.approve(address(args.positionManager), args.amountADesired);
    args.tokenB.approve(address(args.positionManager), args.amountBDesired);

    if (address(args.tokenA) < address(args.tokenB)) {
        vars.tokens[0] = address(args.tokenA);
        vars.tokens[1] = address(args.tokenB);
        vars.amounts[0] = args.amountADesired;
        vars.amounts[1] = args.amountBDesired;
        // inverse price if token1 goes first
        vars.price = DECIMAL_PRECISION * DECIMAL_PRECISION / args.upscaledPrice;
    } else {
        vars.tokens[0] = address(args.tokenB);
        vars.tokens[1] = address(args.tokenA);
        vars.amounts[0] = args.amountBDesired;
        vars.amounts[1] = args.amountADesired;
        vars.price = args.upscaledPrice;
    }

    vars.sqrtPriceX96 = priceToSqrtPriceX96(vars.price);

    pool = address(0x870177d19151F102E519F145d8cf5965Ae43c288);

    vars.TICK_SPACING = ICLPool(pool).tickSpacing();
    (, vars.tick,,,,) = ICLPool(pool).slot0();
    vars.tickLower = (vars.tick - 6000) / vars.TICK_SPACING * vars.TICK_SPACING;
    vars.tickUpper = (vars.tick + 6000) / vars.TICK_SPACING * vars.TICK_SPACING;

    ISlipstreamNonfungiblePositionManager.MintParams memory params = ISlipstreamNonfungiblePositionManager.MintParams({
        token0: vars.tokens[0],
        token1: vars.tokens[1],
        tickSpacing: vars.TICK_SPACING,
        tickLower: vars.tickLower,
        tickUpper: vars.tickUpper,
        amount0Desired: vars.amounts[0],
        amount1Desired: vars.amounts[1],
        amount0Min: 0,
        amount1Min: 0,
        recipient: args.deployer,
        deadline: block.timestamp + 10 minutes,
        sqrtPriceX96: 0 // vars.sqrtPriceX96 // if != 0, tries to create a new pool
    });

    (,, amountA, amountB) = args.positionManager.mint(params);
}

function initSlipstreamLiquidityPool(InitSlipstreamLiquidityPoolArgs memory args)
    returns (address pool, uint256 amountA, uint256 amountB)
{
    InitSlipstreamLiquidityPoolVars memory vars;

    args.tokenA.approve(address(args.positionManager), args.amountADesired);
    args.tokenB.approve(address(args.positionManager), args.amountBDesired);

    if (address(args.tokenA) < address(args.tokenB)) {
        vars.tokens[0] = address(args.tokenA);
        vars.tokens[1] = address(args.tokenB);
        vars.amounts[0] = args.amountADesired;
        vars.amounts[1] = args.amountBDesired;
        // inverse price if token1 goes first
        vars.price = DECIMAL_PRECISION * DECIMAL_PRECISION / args.upscaledPrice;
    } else {
        vars.tokens[0] = address(args.tokenB);
        vars.tokens[1] = address(args.tokenA);
        vars.amounts[0] = args.amountBDesired;
        vars.amounts[1] = args.amountADesired;
        vars.price = args.upscaledPrice;
    }

    vars.sqrtPriceX96 = priceToSqrtPriceX96(vars.price);

    pool = args.poolFactory.createPool(vars.tokens[0], vars.tokens[1], args.tickSpacing, vars.sqrtPriceX96);

    vars.TICK_SPACING = ICLPool(pool).tickSpacing();
    (, vars.tick,,,,) = ICLPool(pool).slot0();
    vars.tickLower = (vars.tick - 6000) / vars.TICK_SPACING * vars.TICK_SPACING;
    vars.tickUpper = (vars.tick + 6000) / vars.TICK_SPACING * vars.TICK_SPACING;

    ISlipstreamNonfungiblePositionManager.MintParams memory params = ISlipstreamNonfungiblePositionManager.MintParams({
        token0: vars.tokens[0],
        token1: vars.tokens[1],
        tickSpacing: vars.TICK_SPACING,
        tickLower: vars.tickLower,
        tickUpper: vars.tickUpper,
        amount0Desired: vars.amounts[0],
        amount1Desired: vars.amounts[1],
        amount0Min: 0,
        amount1Min: 0,
        recipient: args.deployer,
        deadline: block.timestamp + 10 minutes,
        sqrtPriceX96: 0 // vars.sqrtPriceX96 // if != 0, tries to create a new pool
    });

    (,, amountA, amountB) = args.positionManager.mint(params);
}

function priceToSqrtPriceX96(uint256 _price) pure returns (uint160 sqrtPriceX96) {
    if (_price > (1 << 64)) {
        sqrtPriceX96 = uint160(Math.sqrt(_price / DECIMAL_PRECISION) << 96);
    } else {
        sqrtPriceX96 = uint160(Math.sqrt((_price << 192) / DECIMAL_PRECISION));
    }
}
