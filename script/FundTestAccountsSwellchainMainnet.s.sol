// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/Interfaces/IWETH.sol";

contract FundTestAccountsSwellchainMainnet is Script {
    struct Coll {
        IERC20 token;
        address whale;
        uint256 amount;
    }

    IWETH weth = IWETH(0x4200000000000000000000000000000000000006);
    IERC20 rsweth = IERC20(0x18d33689AE5d02649a859A1CF16c9f0563975258);
    IERC20 weeth = IERC20(0xA6cB988942610f6731e664379D15fFcfBf282b44);
    IERC20 sweth = IERC20(0x09341022ea237a4DB1644DE7CCf8FA0e489D85B7);
    IERC20 swell = IERC20(0x2826D136F5630adA89C1678b64A61620Aab77Aea);
    IERC20 usdc = IERC20(0x99a38322cAF878Ef55AE4d0Eda535535eF8C7960);

    function run() external {
        if (!(block.chainid == 31337 || block.chainid == 7566690)) revert("Only for local testing");

        Coll[] memory colls = new Coll[](5);
        colls[0] = Coll(rsweth, 0x5c9E30def85334e587Cf36EB07bdd6A72Bf1452d, 1 ether);
        colls[1] = Coll(weeth, 0xf0bb20865277aBd641a307eCe5Ee04E79073416C, 1 ether);
        colls[2] = Coll(sweth, 0xE1441C61bfA1F10d9Ce1Dc453b1Ec7D57516D349, 1 ether);
        colls[3] = Coll(swell, 0x1AB4973a48dc892Cd9971ECE8e01DcC7688f8F23, 200_000 ether);
        colls[4] = Coll(usdc, 0xc68Da210A520dA375eD6cCCb88F2f44aA3033c47, 10000000);

        // Anvil default accounts
        uint256[] memory demoAccounts = new uint256[](1);
        demoAccounts[0] = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        // fund all whales for gas so we can broadcast from them
        // for (uint256 i = 0; i < colls.length; i++) {
        //     console.log(vm.addr(demoAccounts[7]).balance);
        //     vm.broadcast(demoAccounts[7]);
        //     (bool success,) = payable(colls[i].whale).call{value: 0.1 ether}("");
        //     require(success, "Funding whale failed");
        // }

        for (uint256 i = 0; i < demoAccounts.length; i++) {
            address addr = vm.addr(demoAccounts[i]);

            vm.broadcast(addr);
            weth.deposit{value: 500 ether}();

            // all collaterals
            for (uint256 j = 0; j < colls.length - 1; j++) {
                vm.broadcast(colls[j].whale);
                colls[j].token.transfer(addr, colls[j].amount);
            }
        }

        // fund the deployer with usdc
        vm.broadcast(colls[4].whale);
        colls[4].token.transfer(vm.addr(demoAccounts[0]), colls[4].amount);
    }
}
