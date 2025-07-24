// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/Interfaces/IWETH.sol";

contract FundTestAccountsScrollMainnet is Script {
    struct Coll {
        IERC20 token;
        address whale;
        uint256 amount;
    }

    IWETH weth = IWETH(0x5300000000000000000000000000000000000004);
    IERC20 wsteth = IERC20(0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32);
    IERC20 weeth = IERC20(0x01f0a31698C4d065659b9bdC21B3610292a1c506);
    IERC20 scroll = IERC20(0xd29687c813D741E2F938F4aC377128810E217b1b);

    function run() external {
        if (block.chainid != 31337) revert("Only for local testing");

        Coll[] memory colls = new Coll[](3);
        colls[0] = Coll(wsteth, 0x99967871e6C4F9a5185aBC57eDeDE9e9540191F6, 50 ether);
        colls[1] = Coll(weeth, 0xe67e43b831A541c5Fa40DE52aB0aFbE311514E64, 50 ether);
        colls[2] = Coll(scroll, 0x212499E4E77484E565E1965Ea220D30B1c469233, 1_000_000 ether);

        // Anvil default accounts
        uint256[] memory demoAccounts = new uint256[](8);
        demoAccounts[0] = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        demoAccounts[1] = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        demoAccounts[2] = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        demoAccounts[3] = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
        demoAccounts[4] = 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a;
        demoAccounts[5] = 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba;
        demoAccounts[6] = 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e;
        demoAccounts[7] = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

        // fund all whales for gas so we can broadcast from them
        for (uint256 i = 0; i < colls.length; i++) {
            console.log(vm.addr(demoAccounts[7]).balance);
            vm.broadcast(demoAccounts[7]);
            (bool success,) = payable(colls[i].whale).call{value: 0.1 ether}("");
            require(success, "Funding whale failed");
        }

        for (uint256 i = 0; i < demoAccounts.length; i++) {
            address addr = vm.addr(demoAccounts[i]);

            vm.broadcast(addr);
            weth.deposit{value: 500 ether}();

            // all collaterals
            for (uint256 j = 0; j < colls.length; j++) {
                vm.broadcast(colls[j].whale);
                colls[j].token.transfer(addr, colls[j].amount);
            }
        }
    }
}
