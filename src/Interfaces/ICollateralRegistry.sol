// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IBoldToken.sol";
import "./ITroveManager.sol";

interface ICollateralRegistry {
    function baseRate() external view returns (uint256);
    function lastFeeOperationTime() external view returns (uint256);

    function redeemCollateral(uint256 _boldamount, uint256 _maxIterations, uint256 _maxFeePercentage) external;

    // getters
    function totalCollaterals() external view returns (uint256);
    function getToken(uint256 _index) external view returns (IERC20Metadata);
    function getTroveManager(uint256 _index) external view returns (ITroveManager);
    function getTokenCap(uint256 _index) external view returns (uint256);
    function getTokenCapByAddress(address _troveManagerAddress) external view returns (uint256);
    function boldToken() external view returns (IBoldToken);

    function getRedemptionRate() external view returns (uint256);
    function getRedemptionRateWithDecay() external view returns (uint256);
    function getRedemptionRateForRedeemedAmount(uint256 _redeemAmount) external view returns (uint256);

    function getRedemptionFeeWithDecay(uint256 _ETHDrawn) external view returns (uint256);
    function getEffectiveRedemptionFeeInBold(uint256 _redeemAmount) external view returns (uint256);

    // Governance functions

    function addCollateral(IERC20Metadata _token, ITroveManager _troveManager, uint256 _maxCap) external;
    function setTroveCCR(uint256 _index, uint256 _newValue) external;
    function setTroveMCR(uint256 _index, uint256 _newValue) external;
    function setTroveSCR(uint256 _index, uint256 _newValue) external;
    function setSPYieldSplit(uint256 _index, uint256 _newValue) external;
    function decreaseMinAnnualInterestRate(uint256 _index, uint256 _minAnnualInterestRate) external;
    function setInterestRouter(uint256 _index, address _newInterestRouter) external;
    function setTokenCap(uint256 _index, uint256 _newValue) external;

    // Emergency Response functions
    function shutdownBranch(uint256 _index) external;
}
