// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/Interfaces/IBorrowerOperations.sol";
import "src/Interfaces/IAddressesRegistry.sol";
import "src/Interfaces/ITroveManager.sol";
import "src/Interfaces/IBoldToken.sol";
import "src/Interfaces/ICollSurplusPool.sol";
import "src/Interfaces/ISortedTroves.sol";
import "src/Dependencies/LiquityBase.sol";
import "src/Dependencies/AddRemoveManagers.sol";
import "src/Types/LatestTroveData.sol";
import "src/Types/LatestBatchData.sol";
import "src/Quill/Interfaces/ISequencerSentinel.sol";

import "src/BorrowerOperations.sol";

library BorrowerOperationsSupportingLib {
    error TCRBelowCCR();
    error RepaymentNotMatchingCollWithdrawal();
    error ICRBelowMCR();
    error ICRBelowMCRPlusBCR();

    using SafeERC20 for IERC20;

    // this function was originally an internal one from BorrowerOperations,
    // moved here from BorrowerOperations as a workaround for contract size limit
    function pullCollAndSendToActivePool(IActivePool _activePool, uint256 _amount, IERC20 collToken) external {
        // Send Coll tokens from sender to active pool
        collToken.safeTransferFrom(msg.sender, address(_activePool), _amount);
        // Make sure Active Pool accountancy is right
        _activePool.accountForReceivedColl(_amount);
    }

    // this function was originally an internal one from BorrowerOperations,
    // moved here from BorrowerOperations as a workaround for contract size limit
    function requireValidAdjustmentInCurrentMode(
        TroveChange memory _troveChange,
        uint256 _price,
        uint256 _newICR,
        bool _isBelowCriticalThreshold,
        bool _isTroveInBatch
    ) external view {
        /*
         * Below Critical Threshold, it is not permitted:
         *
         * - Borrowing, unless it brings TCR up to CCR again
         * - Collateral withdrawal except accompanied by a debt repayment of at least the same value
         *
         * In Normal Mode, ensure:
         *
         * - The adjustment won't pull the TCR below CCR
         *
         * In Both cases:
         * - The new ICR is above MCR
         */
        if (_isTroveInBatch) {
            requireICRisAboveMCRPlusBCR(_newICR);
        } else {
            requireICRisAboveMCR(_newICR);
        }

        uint256 newTCR = getNewTCRFromTroveChange(_troveChange, _price);
        if (_isBelowCriticalThreshold) {
            _requireNoBorrowingUnlessNewTCRisAboveCCR(_troveChange.debtIncrease, newTCR);
            _requireDebtRepaymentGeCollWithdrawal(_troveChange, _price);
        } else {
            // if Normal Mode
            _requireNewTCRisAboveCCR(newTCR);
        }
    }

    function _requireNoBorrowingUnlessNewTCRisAboveCCR(uint256 _debtIncrease, uint256 _newTCR) internal view {
        if (_debtIncrease > 0 && _newTCR < bo().CCR()) {
            revert TCRBelowCCR();
        }
    }

    function _requireNewTCRisAboveCCR(uint256 _newTCR) internal view {
        if (_newTCR < bo().CCR()) {
            revert TCRBelowCCR();
        }
    }

    // this function is actually duplicated in BorrowerOperations,
    // but removing it from there is not worth the extract cost of an external call
    function requireICRisAboveMCR(uint256 _newICR) internal view {
        if (_newICR < bo().MCR()) {
            revert ICRBelowMCR();
        }
    }

    // this function is also duplicated in BorrowerOperations,
    // but removing it from there is not worth the extract cost of an external call
    function requireICRisAboveMCRPlusBCR(uint256 _newICR) internal view {
        if (_newICR < bo().MCR() + bo().BCR()) {
            revert ICRBelowMCRPlusBCR();
        }
    }

    function _requireDebtRepaymentGeCollWithdrawal(TroveChange memory _troveChange, uint256 _price) internal pure {
        if ((_troveChange.debtDecrease * DECIMAL_PRECISION < _troveChange.collDecrease * _price)) {
            revert RepaymentNotMatchingCollWithdrawal();
        }
    }

    // this function is actually duplicated in BorrowerOperations,
    // but removing it from there is not worth the extract cost of an external call
    function getNewTCRFromTroveChange(TroveChange memory _troveChange, uint256 _price)
        public
        view
        returns (uint256 newTCR)
    {
        uint256 totalColl = bo().getEntireBranchColl();
        totalColl += _troveChange.collIncrease;
        totalColl -= _troveChange.collDecrease;

        uint256 totalDebt = bo().getEntireBranchDebt();
        totalDebt += _troveChange.debtIncrease;
        totalDebt += _troveChange.upfrontFee;
        totalDebt -= _troveChange.debtDecrease;

        newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price);
    }

    function bo() internal view returns (BorrowerOperations) {
        return BorrowerOperations(address(this));
    }
}
