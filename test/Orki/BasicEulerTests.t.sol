// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IEulerVault } from "src/Zappers/Modules/FlashLoans/Euler/IEulerVault.sol";

// weth:  --
// rsweth: 
// sweth: 

contract EulerMockProvider {
    using SafeERC20 for IERC20;

    IEulerVault public eVault;
    IERC20 public token;
    uint256 amountRequested;

    constructor(address _eVault, address _token) {
        eVault = IEulerVault(_eVault);
        token = IERC20(_token);
    }

    function makeflashLoan(uint256 _amount, bytes calldata data) public {
        amountRequested = _amount;
        eVault.flashLoan(amountRequested, data);
    }

    function onFlashLoan(bytes calldata /* data */) public {
        // repay the loan -- zero fee
        token.safeTransfer(address(eVault), amountRequested);
    }
}

contract BasicEulerTests is Test {

    event Transfer(address indexed from, address indexed to, uint256 value);

    address constant WETH_CA = 0x4200000000000000000000000000000000000006;
    address constant RSWETH_CA = 0x18d33689AE5d02649a859A1CF16c9f0563975258;
    address constant SWETH_CA = 0x09341022ea237a4DB1644DE7CCf8FA0e489D85B7;

    address constant WETH_VAULT_CA = 0x49C077B74292aA8F589d39034Bf9C1Ed1825a608;
    address constant RSWETH_VAULT_CA = 0x1773002742A2bCc7666e38454F761CE8fe613DE5;
    address constant SWETH_VAULT_CA = 0xf34253Ec3Dd0cb39C29cF5eeb62161FB350A9d14;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("swellchain"));
    }

    function test_flashLoan() public {
        EulerMockProvider provider = new EulerMockProvider(WETH_VAULT_CA, WETH_CA);
  
        vm.expectEmit(true, true, false, true);
        emit Transfer(WETH_VAULT_CA, address(provider), 1 ether);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(provider), WETH_VAULT_CA, 1 ether);

        provider.makeflashLoan(1 ether, "data");
    }
}