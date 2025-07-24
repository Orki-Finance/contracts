// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../Interfaces/ILeverageZapper.sol";
import "../../Interfaces/IFlashLoanReceiver.sol";
import "../../Interfaces/IFlashLoanProvider.sol";
import { IEulerVault } from "./Euler/IEulerVault.sol";

import "forge-std/console.sol";

contract EulerFlashLoan is IFlashLoanProvider {
    using SafeERC20 for IERC20;

    IFlashLoanReceiver public receiver;
    IEulerVault public immutable eVault;
    IERC20 public immutable token;

    constructor(address _eVault, address _token) {
        eVault = IEulerVault(_eVault);
        token = IERC20(_token);
    }

    function makeFlashLoan(IERC20 /*_token*/, uint256 _amount, Operation _operation, bytes calldata _params) external {

        // Data for the callback receiveFlashLoan
        bytes memory userData;
        if (_operation == Operation.OpenTrove) {
            (address sender, ILeverageZapper.OpenLeveragedTroveParams memory openTroveParams) =
                abi.decode(_params, (address, ILeverageZapper.OpenLeveragedTroveParams));
            userData = abi.encode(_operation, sender, openTroveParams);
        } else if (_operation == Operation.LeverUpTrove) {
            ILeverageZapper.LeverUpTroveParams memory leverUpTroveParams =
                abi.decode(_params, (ILeverageZapper.LeverUpTroveParams));
            userData = abi.encode(_operation, leverUpTroveParams);
        } else if (_operation == Operation.LeverDownTrove) {
            ILeverageZapper.LeverDownTroveParams memory leverDownTroveParams =
                abi.decode(_params, (ILeverageZapper.LeverDownTroveParams));
            userData = abi.encode(_operation, leverDownTroveParams);
        } else if (_operation == Operation.CloseTrove) {
            IZapper.CloseTroveParams memory closeTroveParams = abi.decode(_params, (IZapper.CloseTroveParams));
            userData = abi.encode(_operation, closeTroveParams);
        } else {
            revert("LZ: Wrong Operation");
        }

        receiver = IFlashLoanReceiver(msg.sender);

        eVault.flashLoan(_amount, userData);
    }

    function onFlashLoan( bytes calldata userData ) external {
        require(msg.sender == address(eVault), "Caller is not Euler");
        require(address(receiver) != address(0), "Flash loan not properly initiated");

        // Reset receiver
        IFlashLoanReceiver _receiver = receiver;
        receiver = IFlashLoanReceiver(address(0));
        uint256 repayAmount = 0;

        // decode and operation
        Operation operation = abi.decode(userData[0:32], (Operation));
        
        if (operation == Operation.OpenTrove) {
            // Open
            // decode params
            (address sender, ILeverageZapper.OpenLeveragedTroveParams memory openTroveParams) =
                abi.decode(userData[32:], (address, ILeverageZapper.OpenLeveragedTroveParams));
            repayAmount = openTroveParams.flashLoanAmount;
            // We send only effective flash loan, keeping fees here
            token.safeTransfer(address(_receiver), repayAmount);
            // Zapper callback
            _receiver.receiveFlashLoanOnOpenLeveragedTrove(sender, openTroveParams, repayAmount);
        } else if (operation == Operation.LeverUpTrove) {
            // Lever up
            // decode params
            ILeverageZapper.LeverUpTroveParams memory leverUpTroveParams =
                abi.decode(userData[32:], (ILeverageZapper.LeverUpTroveParams));
            repayAmount = leverUpTroveParams.flashLoanAmount;
            // We send only effective flash loan, keeping fees here
            token.safeTransfer(address(_receiver), repayAmount);
            // Zapper callback
            _receiver.receiveFlashLoanOnLeverUpTrove(leverUpTroveParams, repayAmount);
        } else if (operation == Operation.LeverDownTrove) {
            // Lever down
            // decode params
            ILeverageZapper.LeverDownTroveParams memory leverDownTroveParams =
                abi.decode(userData[32:], (ILeverageZapper.LeverDownTroveParams));
            repayAmount = leverDownTroveParams.flashLoanAmount;
            // We send only effective flash loan, keeping fees here
            token.safeTransfer(address(_receiver), repayAmount);
            // Zapper callback
            _receiver.receiveFlashLoanOnLeverDownTrove(leverDownTroveParams, repayAmount);
        } else if (operation == Operation.CloseTrove) {
            // Close trove
            // decode params
            IZapper.CloseTroveParams memory closeTroveParams = abi.decode(userData[32:], (IZapper.CloseTroveParams));
            repayAmount = closeTroveParams.flashLoanAmount;
            // We send only effective flash loan, keeping fees here
            token.safeTransfer(address(_receiver), repayAmount);
            // Zapper callback
            _receiver.receiveFlashLoanOnCloseTroveFromCollateral(closeTroveParams, repayAmount);
        } else {
            revert("LZ: Wrong Operation");
        }

        token.safeTransfer(address(eVault), repayAmount);
    }
}