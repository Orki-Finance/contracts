// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// dev: reference interface: https://github.com/euler-xyz/euler-vault-kit/blob/master/src/EVault/IEVault.sol#L259-L264
//      reference implementation: https://github.com/euler-xyz/euler-vault-kit/blob/master/src/EVault/modules/Borrowing.sol#L144-L158
// orki targets:
//      weth: 0x49C077B74292aA8F589d39034Bf9C1Ed1825a608 -- https://app.euler.finance/vault/0x49C077B74292aA8F589d39034Bf9C1Ed1825a608?network=swellchain
//      rsweth: 0x1773002742A2bCc7666e38454F761CE8fe613DE5
//      sweth: 0xf34253Ec3Dd0cb39C29cF5eeb62161FB350A9d14
//      swell: missing
//      swbtc: missing
interface IEulerVault {

    /// @notice Request a flash-loan. A onFlashLoan() callback in msg.sender will be invoked, which must repay the loan
    /// to the main Euler address prior to returning.
    /// @param amount In asset units
    /// @param data Passed through to the onFlashLoan() callback, so contracts don't need to store transient data in
    /// storage
    function flashLoan(uint256 amount, bytes calldata data) external;

}