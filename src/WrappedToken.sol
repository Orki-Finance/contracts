// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract WrappedToken is ERC20Wrapper {
    IERC20Metadata private immutable underlyingToken;
    uint8 private immutable wrappedDecimals;
    uint8 private immutable decimalDiff;

    error InvalidDecimals();

    constructor(IERC20Metadata _underlyingToken, uint8 _wrappedDecimals)
        ERC20(
            string(abi.encodePacked("Orki Wrapped ", _underlyingToken.name())), // TODO: validate this
            string(abi.encodePacked("w", _underlyingToken.symbol())) // TODO: validate this
        )
        ERC20Wrapper(_underlyingToken)
    {
        if (_wrappedDecimals < _underlyingToken.decimals()) {
            revert InvalidDecimals();
        }

        underlyingToken = _underlyingToken;
        wrappedDecimals = _wrappedDecimals;
        decimalDiff = _wrappedDecimals - _underlyingToken.decimals();
    }

    function decimals() public view override returns (uint8) {
        return wrappedDecimals;
    }

    function depositFor(address account, uint256 underlyingValue) public override returns (bool) {
        address sender = _msgSender();

        if (account == address(this)) {
            revert ERC20InvalidReceiver(account);
        }

        SafeERC20.safeTransferFrom(underlyingToken, sender, address(this), underlyingValue);
        _mint(account, underlyingValue * (10 ** decimalDiff));

        return true;
    }

    function withdrawTo(address account, uint256 underlyingValue) public override returns (bool) {
        if (account == address(this)) {
            revert ERC20InvalidReceiver(account);
        }

        _burn(_msgSender(), underlyingValue * (10 ** decimalDiff));
        SafeERC20.safeTransfer(underlyingToken, account, underlyingValue);

        return true;
    }
}
