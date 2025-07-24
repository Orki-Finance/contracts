pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WrappedToken} from "src/WrappedToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract WrappedTokenTest is Test {
    address user = address(0x1);

    uint256 constant USDC_PRECISION = 10 ** 6;
    uint256 constant swBTC_PRECISION = 10 ** 8;
    uint256 constant WRAPPED_PRECISION = 10 ** 18;

    IERC20Metadata constant USDC = IERC20Metadata(0x99a38322cAF878Ef55AE4d0Eda535535eF8C7960);
    IERC20Metadata constant swBTC = IERC20Metadata(0x1cf7b5f266A0F39d6f9408B90340E3E71dF8BF7B);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("swellchain"));
    }

    function test_initialization() public {
        WrappedToken wrappedUSDC = new WrappedToken(USDC, 18);
        assertEq(wrappedUSDC.name(), "Orki Wrapped USDC");
        assertEq(wrappedUSDC.name(), string(abi.encodePacked("Orki Wrapped ", USDC.name())));
        assertEq(wrappedUSDC.symbol(), "wUSDC");
        assertEq(wrappedUSDC.symbol(), string(abi.encodePacked("w", USDC.symbol())));

        WrappedToken wrappedswBTC = new WrappedToken(swBTC, 18);
        assertEq(wrappedswBTC.name(), "Orki Wrapped swBTC");
        assertEq(wrappedswBTC.name(), string(abi.encodePacked("Orki Wrapped ", swBTC.name())));
        assertEq(wrappedswBTC.symbol(), "wswBTC");
        assertEq(wrappedswBTC.symbol(), string(abi.encodePacked("w", swBTC.symbol())));
    }

    function test_initialization_InvalidDecimals() public {
        vm.expectPartialRevert(WrappedToken.InvalidDecimals.selector);
        new WrappedToken(USDC, 5);
        new WrappedToken(USDC, 6);
        new WrappedToken(USDC, 7);

        vm.expectPartialRevert(WrappedToken.InvalidDecimals.selector);
        new WrappedToken(swBTC, 7);
        new WrappedToken(swBTC, 8);
        new WrappedToken(swBTC, 9);
    }

    function test_USDC_depositFor() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 18);

        deal(address(USDC), user, 1);
        assertEq(USDC.balanceOf(user), 1);

        vm.startPrank(user);
        USDC.approve(address(wrappedToken), 1);
        wrappedToken.depositFor(user, 1);
        vm.stopPrank();

        assertEq(USDC.balanceOf(user), 0);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION / USDC_PRECISION);
    }

    function test_USDC_depositFor_fuzzy(uint256 usdcValue) public {
        usdcValue = bound(usdcValue, 1, 1e48);

        WrappedToken wrappedToken = new WrappedToken(USDC, 18);

        deal(address(USDC), user, usdcValue);
        assertEq(USDC.balanceOf(user), usdcValue);

        vm.startPrank(user);
        USDC.approve(address(wrappedToken), usdcValue);
        wrappedToken.depositFor(user, usdcValue);
        vm.stopPrank();

        assertEq(USDC.balanceOf(user), 0);
        assertEq(wrappedToken.balanceOf(user), usdcValue * (WRAPPED_PRECISION / USDC_PRECISION));
    }

    function test_USDC_withdrawTo() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 18);

        deal(address(wrappedToken), user, WRAPPED_PRECISION);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION);

        deal(address(USDC), address(wrappedToken), USDC_PRECISION);
        assertEq(USDC.balanceOf(address(wrappedToken)), USDC_PRECISION);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, USDC_PRECISION);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(wrappedToken)), 0);
        assertEq(USDC.balanceOf(user), USDC_PRECISION);
        assertEq(wrappedToken.balanceOf(user), 0);
    }

    function test_USDC_withdrawTo_remainders() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 18);

        deal(address(wrappedToken), user, WRAPPED_PRECISION + 1);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION + 1);

        deal(address(USDC), address(wrappedToken), USDC_PRECISION + 1);
        assertEq(USDC.balanceOf(address(wrappedToken)), USDC_PRECISION + 1);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, USDC_PRECISION);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(wrappedToken)), 1);
        assertEq(USDC.balanceOf(user), USDC_PRECISION);
        assertEq(wrappedToken.balanceOf(user), 1);
    }

    function test_USDC_withdrawTo_InsufficientWrappedBalance() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 18);

        deal(address(wrappedToken), user, WRAPPED_PRECISION - 1);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION - 1);

        deal(address(USDC), address(wrappedToken), USDC_PRECISION);
        assertEq(USDC.balanceOf(address(wrappedToken)), USDC_PRECISION);

        vm.startPrank(user);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        wrappedToken.withdrawTo(user, USDC_PRECISION);
        vm.stopPrank();
    }

    function test_USDC_withdrawTo_fuzzy(uint256 usdcValue) public {
        usdcValue = bound(usdcValue, 1, 1e48);

        WrappedToken wrappedToken = new WrappedToken(USDC, 18);

        deal(address(wrappedToken), user, usdcValue * (WRAPPED_PRECISION / USDC_PRECISION));
        assertEq(wrappedToken.balanceOf(user), usdcValue * (WRAPPED_PRECISION / USDC_PRECISION));

        deal(address(USDC), address(wrappedToken), usdcValue);
        assertEq(USDC.balanceOf(address(wrappedToken)), usdcValue);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, usdcValue);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(wrappedToken)), 0);
        assertEq(USDC.balanceOf(user), usdcValue);
        assertEq(wrappedToken.balanceOf(user), 0);
    }

    function test_swBTC_depositFor() public {
        WrappedToken wrappedToken = new WrappedToken(swBTC, 18);

        deal(address(swBTC), user, 1);
        assertEq(swBTC.balanceOf(user), 1);

        vm.startPrank(user);
        swBTC.approve(address(wrappedToken), 1);
        wrappedToken.depositFor(user, 1);
        vm.stopPrank();

        assertEq(swBTC.balanceOf(user), 0);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION / swBTC_PRECISION);
    }

    function test_swBTC_depositFor_fuzzy(uint256 swBTCValue) public {
        swBTCValue = bound(swBTCValue, 1, 1e48);

        WrappedToken wrappedToken = new WrappedToken(swBTC, 18);

        deal(address(swBTC), user, swBTCValue);
        assertEq(swBTC.balanceOf(user), swBTCValue);

        vm.startPrank(user);
        swBTC.approve(address(wrappedToken), swBTCValue);
        wrappedToken.depositFor(user, swBTCValue);
        vm.stopPrank();

        assertEq(swBTC.balanceOf(user), 0);
        assertEq(wrappedToken.balanceOf(user), swBTCValue * (WRAPPED_PRECISION / swBTC_PRECISION));
    }

    function test_swBTC_withdrawTo() public {
        WrappedToken wrappedToken = new WrappedToken(swBTC, 18);

        deal(address(wrappedToken), user, WRAPPED_PRECISION);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION);

        deal(address(swBTC), address(wrappedToken), swBTC_PRECISION);
        assertEq(swBTC.balanceOf(address(wrappedToken)), swBTC_PRECISION);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, swBTC_PRECISION);
        vm.stopPrank();

        assertEq(swBTC.balanceOf(address(wrappedToken)), 0);
        assertEq(swBTC.balanceOf(user), swBTC_PRECISION);
        assertEq(wrappedToken.balanceOf(user), 0);
    }

    function test_swBTC_withdrawTo_remainders() public {
        WrappedToken wrappedToken = new WrappedToken(swBTC, 18);

        deal(address(wrappedToken), user, WRAPPED_PRECISION + 1);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION + 1);

        deal(address(swBTC), address(wrappedToken), swBTC_PRECISION + 1);
        assertEq(swBTC.balanceOf(address(wrappedToken)), swBTC_PRECISION + 1);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, swBTC_PRECISION);
        vm.stopPrank();

        assertEq(swBTC.balanceOf(address(wrappedToken)), 1);
        assertEq(swBTC.balanceOf(user), swBTC_PRECISION);
        assertEq(wrappedToken.balanceOf(user), 1);
    }

    function test_swBTC_withdrawTo_InsufficientWrappedBalance() public {
        WrappedToken wrappedToken = new WrappedToken(swBTC, 18);

        deal(address(wrappedToken), user, WRAPPED_PRECISION - 1);
        assertEq(wrappedToken.balanceOf(user), WRAPPED_PRECISION - 1);

        deal(address(swBTC), address(wrappedToken), swBTC_PRECISION);
        assertEq(swBTC.balanceOf(address(wrappedToken)), swBTC_PRECISION);

        vm.startPrank(user);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        wrappedToken.withdrawTo(user, swBTC_PRECISION);
        vm.stopPrank();
    }

    function test_swBTC_withdrawTo_fuzzy(uint256 swBTCValue) public {
        swBTCValue = bound(swBTCValue, 1, 1e48);

        WrappedToken wrappedToken = new WrappedToken(swBTC, 18);

        deal(address(wrappedToken), user, swBTCValue * (WRAPPED_PRECISION / swBTC_PRECISION));
        assertEq(wrappedToken.balanceOf(user), swBTCValue * (WRAPPED_PRECISION / swBTC_PRECISION));

        deal(address(swBTC), address(wrappedToken), swBTCValue);
        assertEq(swBTC.balanceOf(address(wrappedToken)), swBTCValue);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, swBTCValue);
        vm.stopPrank();

        assertEq(swBTC.balanceOf(address(wrappedToken)), 0);
        assertEq(swBTC.balanceOf(user), swBTCValue);
        assertEq(wrappedToken.balanceOf(user), 0);
    }

    function test_sameDecimals_depositFor() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 6);

        deal(address(USDC), user, 1);
        assertEq(USDC.balanceOf(user), 1);

        vm.startPrank(user);
        USDC.approve(address(wrappedToken), 1);
        wrappedToken.depositFor(user, 1);
        vm.stopPrank();

        assertEq(USDC.balanceOf(user), 0);
        assertEq(wrappedToken.balanceOf(user), 1);
    }

    function test_sameDecimals_depositFor_fuzzy(uint256 value) public {
        value = bound(value, 1, 1e48);

        WrappedToken wrappedToken = new WrappedToken(USDC, 6);

        deal(address(USDC), user, value);
        assertEq(USDC.balanceOf(user), value);

        vm.startPrank(user);
        USDC.approve(address(wrappedToken), value);
        wrappedToken.depositFor(user, value);
        vm.stopPrank();

        assertEq(USDC.balanceOf(user), 0);
        assertEq(wrappedToken.balanceOf(user), value);
    }

    function test_sameDecimals_withdrawTo() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 6);

        deal(address(wrappedToken), user, 1);
        assertEq(wrappedToken.balanceOf(user), 1);

        deal(address(USDC), address(wrappedToken), 1);
        assertEq(USDC.balanceOf(address(wrappedToken)), 1);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, 1);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(wrappedToken)), 0);
        assertEq(USDC.balanceOf(user), 1);
        assertEq(wrappedToken.balanceOf(user), 0);
    }

    function test_sameDecimals_withdrawTo_remainders() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 6);

        deal(address(wrappedToken), user, 2);
        assertEq(wrappedToken.balanceOf(user), 2);

        deal(address(USDC), address(wrappedToken), 2);
        assertEq(USDC.balanceOf(address(wrappedToken)), 2);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, 1);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(wrappedToken)), 1);
        assertEq(USDC.balanceOf(user), 1);
        assertEq(wrappedToken.balanceOf(user), 1);
    }

    function test_sameDecimals_withdrawTo_InsufficientWrappedBalance() public {
        WrappedToken wrappedToken = new WrappedToken(USDC, 6);

        deal(address(wrappedToken), user, 1);
        assertEq(wrappedToken.balanceOf(user), 1);

        deal(address(USDC), address(wrappedToken), 2);
        assertEq(USDC.balanceOf(address(wrappedToken)), 2);

        vm.startPrank(user);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        wrappedToken.withdrawTo(user, 2);
        vm.stopPrank();
    }

    function test_sameDecimals_withdrawTo_fuzzy(uint256 value) public {
        value = bound(value, 1, 1e48);

        WrappedToken wrappedToken = new WrappedToken(USDC, 6);

        deal(address(wrappedToken), user, value);
        assertEq(wrappedToken.balanceOf(user), value);

        deal(address(USDC), address(wrappedToken), value);
        assertEq(USDC.balanceOf(address(wrappedToken)), value);

        vm.startPrank(user);
        wrappedToken.withdrawTo(user, value);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(wrappedToken)), 0);
        assertEq(USDC.balanceOf(user), value);
        assertEq(wrappedToken.balanceOf(user), 0);
    }
}
