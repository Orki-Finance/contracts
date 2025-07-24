// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import {QuillUUPSUpgradeable} from "./Quill/QuillUUPSUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./Interfaces/IBoldToken.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {ICollateralRegistry} from "src/Interfaces/ICollateralRegistry.sol";

/*
 * --- Functionality added specific to the BoldToken ---
 *
 * 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Liquity contracts) in external
 * transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending BOLD directly to a Liquity
 * core contract, when they should rather call the right function.
 *
 * 2) sendToPool() and returnFromPool(): functions callable only Liquity core contracts, which move BOLD tokens between Liquity <-> user.
 */

contract BoldToken is QuillUUPSUpgradeable, IBoldToken, ERC20PermitUpgradeable {
    string internal constant _NAME = "Orki USD Stablecoin";
    string internal constant _SYMBOL = "USDK";

    // --- Addresses ---

    address public collateralRegistryAddress;
    mapping(address => bool) troveManagerAddresses;
    mapping(address => bool) stabilityPoolAddresses;
    mapping(address => address) borrowerOperationsToTroveManager;
    mapping(address => bool) activePoolAddresses;

    // --- Events ---
    event BranchAdded(uint256 _collIndex, address _collateralAddress, address _troveManagerAddress);
    event CollateralRegistryAddressChanged(address _newCollateralRegistryAddress);
    event TroveManagerAddressAdded(address _newTroveManagerAddress);
    event StabilityPoolAddressAdded(address _newStabilityPoolAddress);
    event BorrowerOperationsAddressAdded(address _newBorrowerOperationsAddress);
    event ActivePoolAddressAdded(address _newActivePoolAddress);

    // --- Errors ---
    error OverBranchCapLimit(address _troveManagerAddress);

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authority) public virtual initializer {
        __ERC20_init(_NAME, _SYMBOL);
        __ERC20Permit_init(_NAME);
        __QuillUUPSUpgradeable_init(_authority);
    }

    function nonces(address owner) public view override(ERC20PermitUpgradeable, IERC20Permit) returns (uint256) {
        return ERC20PermitUpgradeable.nonces(owner);
    }

    function setBranchAddresses(
        uint256 collIndex,
        address _collateralAddress,
        address _troveManagerAddress,
        address _stabilityPoolAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress
    ) public override {
        _requireCallerIsCollateralRegistry();

        emit BranchAdded(collIndex, _collateralAddress, _troveManagerAddress);

        troveManagerAddresses[_troveManagerAddress] = true;
        emit TroveManagerAddressAdded(_troveManagerAddress);

        stabilityPoolAddresses[_stabilityPoolAddress] = true;
        emit StabilityPoolAddressAdded(_stabilityPoolAddress);

        borrowerOperationsToTroveManager[_borrowerOperationsAddress] = _troveManagerAddress;
        emit BorrowerOperationsAddressAdded(_borrowerOperationsAddress);

        activePoolAddresses[_activePoolAddress] = true;
        emit ActivePoolAddressAdded(_activePoolAddress);
    }

    function setCollateralRegistry(address _collateralRegistryAddress) external override restricted {
        require(collateralRegistryAddress == address(0), "already set");

        collateralRegistryAddress = _collateralRegistryAddress;
        emit CollateralRegistryAddressChanged(_collateralRegistryAddress);
    }

    // --- Functions for intra-Liquity calls ---

    function mint(address _account, uint256 _amount) external override {
        bool isBO = _requireCallerIsBOorAP();

        // if is AP, allow to mint interest, otherwise check for max minting cap
        if (isBO) {
            address _cachedTMAddress = borrowerOperationsToTroveManager[msg.sender];
            uint256 _maxBranchCap =
                ICollateralRegistry(collateralRegistryAddress).getTokenCapByAddress(_cachedTMAddress);
            uint256 _currentBranchCap = ITroveManager(_cachedTMAddress).getEntireBranchDebt();

            // current branch cap already accounts for _amount value
            if (_currentBranchCap > _maxBranchCap) {
                revert OverBranchCapLimit(_cachedTMAddress);
            }
        }

        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        _requireCallerIsCRorBOorTMorSP();
        _burn(_account, _amount);
    }

    function sendToPool(address _sender, address _poolAddress, uint256 _amount) external override {
        _requireCallerIsStabilityPool();
        _transfer(_sender, _poolAddress, _amount);
    }

    function returnFromPool(address _poolAddress, address _receiver, uint256 _amount) external override {
        _requireCallerIsStabilityPool();
        _transfer(_poolAddress, _receiver, _amount);
    }

    // --- External functions ---

    function transfer(address recipient, uint256 amount) public override(ERC20Upgradeable, IERC20) returns (bool) {
        _requireValidRecipient(recipient);
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        public
        override(ERC20Upgradeable, IERC20)
        returns (bool)
    {
        _requireValidRecipient(recipient);
        return super.transferFrom(sender, recipient, amount);
    }

    // --- 'require' functions ---

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && _recipient != address(this),
            "BoldToken: Cannot transfer tokens directly to the Bold token contract or the zero address"
        );
    }

    function _requireCallerIsBOorAP() internal view returns (bool) {
        require(
            _isRegisteredTroveManager(borrowerOperationsToTroveManager[msg.sender]) || activePoolAddresses[msg.sender],
            "BoldToken: Caller is not BO or AP"
        );

        return _isRegisteredTroveManager(borrowerOperationsToTroveManager[msg.sender]);
    }

    function _requireCallerIsCollateralRegistry() internal view {
        require(msg.sender == collateralRegistryAddress, "Bold: Caller is not the CollateralRegistry");
    }

    function _requireCallerIsCRorBOorTMorSP() internal view {
        require(
            msg.sender == collateralRegistryAddress
                || _isRegisteredTroveManager(borrowerOperationsToTroveManager[msg.sender])
                || troveManagerAddresses[msg.sender] || stabilityPoolAddresses[msg.sender],
            "BoldToken: Caller is neither CR nor BorrowerOperations nor TroveManager nor StabilityPool"
        );
    }

    function _requireCallerIsStabilityPool() internal view {
        require(stabilityPoolAddresses[msg.sender], "BoldToken: Caller is not the StabilityPool");
    }

    function _isRegisteredTroveManager(address troveManagerAddress) private pure returns (bool) {
        return troveManagerAddress != address(0);
    }
}
