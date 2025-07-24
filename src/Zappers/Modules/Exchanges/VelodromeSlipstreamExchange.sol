// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../../LeftoversSweep.sol";
import "../../../Interfaces/IBoldToken.sol";
import "src/Zappers/Modules/Exchanges/Slipstream/periphery/ISlipstreamSwapRouter.sol";
import "./UniswapV3/UniPriceConverter.sol";
import "../../Interfaces/IExchange.sol";
import {DECIMAL_PRECISION} from "../../../Dependencies/Constants.sol";

contract VelodromeSlipstreamExchange is LeftoversSweep, UniPriceConverter, IExchange {
    using SafeERC20 for IERC20;

    IERC20 public immutable collToken;
    IBoldToken public immutable boldToken;
    int24 public immutable tickspacing;
    ISlipstreamSwapRouter public immutable slipstreamRouter;

    constructor(IERC20 _collToken, IBoldToken _boldToken, int24 _tickspacing, ISlipstreamSwapRouter _slipstreamRouter) {
        collToken = _collToken;
        boldToken = _boldToken;
        tickspacing = _tickspacing;
        slipstreamRouter = _slipstreamRouter;
    }

    function swapFromBold(uint256 _boldAmount, uint256 _minCollAmount) external {
        ISlipstreamSwapRouter slipstreamRouterCached = slipstreamRouter;

        // Set initial balances to make sure there are not lefovers
        InitialBalances memory initialBalances;
        _setInitialTokensAndBalances(collToken, boldToken, initialBalances);

        boldToken.transferFrom(msg.sender, address(this), _boldAmount);
        boldToken.approve(address(slipstreamRouterCached), _boldAmount);

        ISlipstreamSwapRouter.ExactOutputSingleParams memory params = ISlipstreamSwapRouter.ExactOutputSingleParams({
            tokenIn: address(boldToken),
            tokenOut: address(collToken),
            tickSpacing: tickspacing,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: _minCollAmount,
            amountInMaximum: _boldAmount,
            sqrtPriceLimitX96: 0 // See: https://ethereum.stackexchange.com/a/156018/9205
        });

        slipstreamRouterCached.exactOutputSingle(params);

        // return leftovers to user
        _returnLeftovers(initialBalances);
    }

    function swapToBold(uint256 _collAmount, uint256 _minBoldAmount) external returns (uint256) {
        ISlipstreamSwapRouter slipstreamRouterCached = slipstreamRouter;

        // Set initial balances to make sure there are not lefovers
        InitialBalances memory initialBalances;
        _setInitialTokensAndBalances(collToken, boldToken, initialBalances);

        collToken.safeTransferFrom(msg.sender, address(this), _collAmount);
        collToken.forceApprove(address(slipstreamRouterCached), _collAmount);

        ISlipstreamSwapRouter.ExactInputSingleParams memory params = ISlipstreamSwapRouter.ExactInputSingleParams({
            tokenIn: address(collToken),
            tokenOut: address(boldToken),
            tickSpacing: tickspacing,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: _collAmount,
            amountOutMinimum: _minBoldAmount,
            sqrtPriceLimitX96: 0 // See: https://ethereum.stackexchange.com/a/156018/9205
        });

        uint256 amountOut = slipstreamRouterCached.exactInputSingle(params);

        // return leftovers to user
        _returnLeftovers(initialBalances);

        return amountOut;
    }

    function priceToSqrtPrice(IBoldToken _boldToken, IERC20 _collToken, uint256 _price) public pure returns (uint160) {
        // inverse price if Bold goes first
        uint256 price = _zeroForOne(_boldToken, _collToken) ? DECIMAL_PRECISION * DECIMAL_PRECISION / _price : _price;
        return priceToSqrtPriceX96(price);
    }

    // See: https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/QuoterV2.sol#L207C9-L207C60
    function _zeroForOne(IBoldToken _boldToken, IERC20 _collToken) internal pure returns (bool) {
        return address(_boldToken) < address(_collToken);
    }
}
