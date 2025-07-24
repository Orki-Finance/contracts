// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BoldToken} from "src/BoldToken.sol";
import "../script/InitialLiquidityHelpers.s.sol";
import {DECIMAL_PRECISION} from "src/Dependencies/Constants.sol";
import {ICrocSwapDex} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapDex.sol";
import {ICrocSwapQuery} from "src/Zappers/Modules/Exchanges/CrocSwap/ICrocSwapQuery.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AmbientLiquidityPoolsTest is Test {
    address user = address(0x1);

    uint256 constant USDC_1 = 1e6;
    uint256 constant TOKEN_1 = 1e18;

    uint256 constant USDC_PRECISION = 10 ** 6;

    IERC20Metadata BOLD;
    IERC20Metadata USDC = IERC20Metadata(0x99a38322cAF878Ef55AE4d0Eda535535eF8C7960);
    IERC20Metadata WETH = IERC20Metadata(0x4200000000000000000000000000000000000006);

    ICrocSwapDex crocSwapDex = ICrocSwapDex(0xaAAaAaaa82812F0a1f274016514ba2cA933bF24D);
    ICrocSwapQuery crocSwapQuery = ICrocSwapQuery(0xaab17419F062bB28CdBE82f9FC05E7C47C3F6194);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("swellchain"));
        BOLD = new BoldToken{salt: keccak256(abi.encodePacked(block.timestamp))}();
    }

    function test_initCrocSwapLP_USDC() public {
        deal(address(BOLD), user, TOKEN_1);
        uint256 initialBoldBalance = BOLD.balanceOf(user);
        assertEq(initialBoldBalance, TOKEN_1);

        deal(address(USDC), user, USDC_1);
        uint256 initialUsdcBalance = USDC.balanceOf(user);
        assertEq(initialUsdcBalance, USDC_1);

        (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(address(USDC), address(BOLD));

        vm.startPrank(user);
        USDC.approve(address(crocSwapDex), USDC_1);
        BOLD.approve(address(crocSwapDex), TOKEN_1);
        initCrocSwapPool(crocSwapDex, BOLD, USDC, DECIMAL_PRECISION);
        vm.stopPrank();

        uint128 newPriceRoot = crocSwapQuery.queryCurve(base, quote, CrocSwapDexHelper.POOL_TYPE_INDEX).priceRoot_;
        uint256 priceInUSDQ =
            CrocSwapDexHelper.priceInUSDq(newPriceRoot, address(BOLD), address(USDC), BOLD.decimals(), USDC.decimals());
        assertApproxEqRel(priceInUSDQ, DECIMAL_PRECISION, 1e16); //less than 1% delta
    }

    function test_initCrocSwapLP_ETH(uint256 price) public {
        price = bound(price, 1000 * DECIMAL_PRECISION, 5000 * DECIMAL_PRECISION);
        address ETH_VIRT_ADDR = address(0);

        deal(user, 1000);
        uint256 initialEthBalance = user.balance;
        assertEq(initialEthBalance, 1000);

        deal(address(BOLD), user, TOKEN_1);
        uint256 initialBoldBalance = BOLD.balanceOf(user);
        assertEq(initialBoldBalance, TOKEN_1);

        (address base, address quote) = CrocSwapDexHelper.getQuoteBaseOrder(ETH_VIRT_ADDR, address(BOLD));

        vm.startPrank(user);
        BOLD.approve(address(crocSwapDex), TOKEN_1);
        initCrocSwapETHPool(crocSwapDex, BOLD, price);
        vm.stopPrank();

        uint128 newPriceRoot = crocSwapQuery.queryCurve(base, quote, CrocSwapDexHelper.POOL_TYPE_INDEX).priceRoot_;
        uint256 priceInUSDQ =
            CrocSwapDexHelper.priceInUSDq(newPriceRoot, address(BOLD), ETH_VIRT_ADDR, BOLD.decimals(), 18);
        assertApproxEqRel(priceInUSDQ, price, 1e16); //less than 1% delta
    }
}
