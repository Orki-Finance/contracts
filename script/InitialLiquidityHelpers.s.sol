// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "src/Interfaces/IBorrowerOperations.sol";
import {DECIMAL_PRECISION} from "src/Dependencies/Constants.sol";

import "src/Zappers/Modules/Exchanges/UniswapV3/IUniswapV3Pool.sol";
import "src/Zappers/Modules/Exchanges/UniswapV3/INonfungiblePositionManager.sol";
import {ICrocSwapDex, CrocSwapDexHelper} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapDex.sol";
import {ICrocSwapQuery} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapQuery.sol";
import "src/Zappers/Modules/Exchanges/CrocSwap/Dependencies/SafeCast.sol";

function openInitialLiquidityTrove(
    address deployer,
    IBorrowerOperations borrowerOperations,
    uint256 boldAmount,
    uint256 collAmount,
    uint256 annualInterestRate,
    uint256 maxUpfrontFee
) {
    borrowerOperations.openTrove(
        deployer, // _owner
        0, // _ownerIndex
        collAmount, // _collAmount
        boldAmount, // _boldAmount
        0, // _upperHint
        0, // _lowerHint
        annualInterestRate, // _annualInterestRate
        // type(uint256).max, // _maxUpfrontFee
        maxUpfrontFee, // _maxUpfrontFee
        address(0), // _addManager
        address(0), // _removeManager
        address(0) // _receiver
    );
}

struct ProvideUniV3LiquidityVars {
    uint256 price;
    int24 TICK_SPACING;
    int24 tick;
    int24 tickLower;
    int24 tickUpper;
    address[2] tokens;
    uint256[2] amounts;
}

function provideUniV3Liquidity(
    address deployer,
    INonfungiblePositionManager uniV3PositionManager,
    IERC20 _token1, // USDQ
    IERC20 _token2,
    uint256 _token1Amount,
    uint256 _token2Amount,
    uint256 _price, // 18 decimals
    uint24 _fee
) returns (address uniV3PoolAddress, uint256 amount0, uint256 amount1) {
    ProvideUniV3LiquidityVars memory vars;

    // assert(address(_token1) > address(_token2));

    _token1.approve(address(uniV3PositionManager), _token1Amount);
    _token2.approve(address(uniV3PositionManager), _token2Amount);

    if (address(_token1) < address(_token2)) {
        vars.tokens[0] = address(_token1);
        vars.tokens[1] = address(_token2);
        vars.amounts[0] = _token1Amount;
        vars.amounts[1] = _token2Amount;
        // inverse price if token1 goes first
        vars.price = DECIMAL_PRECISION * DECIMAL_PRECISION / _price;
    } else {
        vars.tokens[0] = address(_token2);
        vars.tokens[1] = address(_token1);
        vars.amounts[0] = _token2Amount;
        vars.amounts[1] = _token1Amount;
        vars.price = _price;
    }

    uniV3PoolAddress = uniV3PositionManager.createAndInitializePoolIfNecessary(
        vars.tokens[0],
        vars.tokens[1],
        _fee,
        priceToSqrtPriceX96(vars.price) // sqrtPriceX96
    );

    vars.TICK_SPACING = IUniswapV3Pool(uniV3PoolAddress).tickSpacing();
    (, vars.tick,,,,,) = IUniswapV3Pool(uniV3PoolAddress).slot0();
    vars.tickLower = (vars.tick - 6000) / vars.TICK_SPACING * vars.TICK_SPACING;
    vars.tickUpper = (vars.tick + 6000) / vars.TICK_SPACING * vars.TICK_SPACING;

    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
        token0: vars.tokens[0],
        token1: vars.tokens[1],
        fee: _fee,
        tickLower: vars.tickLower,
        tickUpper: vars.tickUpper,
        amount0Desired: vars.amounts[0],
        amount1Desired: vars.amounts[1],
        amount0Min: 0,
        amount1Min: 0,
        recipient: deployer,
        deadline: block.timestamp + 600 minutes
    });

    (,, amount0, amount1) = uniV3PositionManager.mint(params);
}

function priceToSqrtPriceX96(uint256 _price) pure returns (uint160 sqrtPriceX96) {
    // overflow vs precision
    if (_price > (1 << 64)) {
        // ~18.4e18
        sqrtPriceX96 = uint160(Math.sqrt(_price / DECIMAL_PRECISION) << 96);
    } else {
        sqrtPriceX96 = uint160(Math.sqrt((_price << 192) / DECIMAL_PRECISION));
    }
}

function initCrocSwapPool(
    ICrocSwapDex crocSwapDex,
    IERC20 _usdq, // quill
    IERC20 _collateral, // collateral
    uint256 _price // 18 decimals in USDq per collateral/token2 -- this is because all our oracles assume USDq as the base
) {
    (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(address(_usdq), address(_collateral));
    bool usdqIsBase = base == address(_usdq);

    if (!usdqIsBase) {
        //invert price
        _price = CrocSwapDexHelper.invertPrice(_price);
    }

    uint256 priceQ64 =
        CrocSwapDexHelper.sqrtPriceQ64(_price, 18, IERC20Metadata(base).decimals(), IERC20Metadata(quote).decimals());

    crocSwapDex.userCmd(
        CrocSwapDexHelper.COLD_PROXY,
        abi.encode(
            CrocSwapDexHelper.FIXED_INITPOOL_SUBCODE,
            base,
            quote,
            CrocSwapDexHelper.POOL_TYPE_INDEX,
            SafeCast.toUint128(priceQ64)
        )
    );
}

function initCrocSwapETHPool(
    ICrocSwapDex crocSwapDex,
    IERC20 _usdq, // quill
    uint256 _price // 18 decimals in USDq per collateral/token2 -- this is because all our oracles assume USDq as the base
) {
    address ETH_VIRT_TOKEN = address(0);
    (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(address(_usdq), ETH_VIRT_TOKEN);
    bool usdqIsBase = base == address(_usdq);

    if (!usdqIsBase) {
        //invert price
        _price = CrocSwapDexHelper.invertPrice(_price);
    }

    // usdq will always be quote. If not, this was a wrong assumption and it's better to fail here
    uint256 priceQ64 = CrocSwapDexHelper.sqrtPriceQ64(_price, 18, 18, IERC20Metadata(quote).decimals());

    // current value is around 176 wei when the price ratio for eth is under 1 (0.002 for usdq)
    crocSwapDex.userCmd{value: 1000}(
        CrocSwapDexHelper.COLD_PROXY,
        abi.encode(
            CrocSwapDexHelper.FIXED_INITPOOL_SUBCODE,
            base,
            quote,
            CrocSwapDexHelper.POOL_TYPE_INDEX,
            SafeCast.toUint128(priceQ64)
        )
    );
}
