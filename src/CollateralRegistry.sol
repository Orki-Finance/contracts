// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./Interfaces/ITroveManager.sol";
import "./Interfaces/IBoldToken.sol";
import "./Quill/Interfaces/ISequencerSentinel.sol";
import "./Dependencies/Constants.sol";
import "./Dependencies/LiquityMath.sol";
import {QuillUUPSUpgradeable} from "./Quill/QuillUUPSUpgradeable.sol";

import "./Interfaces/ICollateralRegistry.sol";

contract CollateralRegistry is QuillUUPSUpgradeable, ICollateralRegistry {
    // See: https://github.com/ethereum/solidity/issues/12587
    uint256 public totalCollaterals;

    IERC20Metadata[] internal tokens;

    ITroveManager[] internal troveManagers;

    uint256[] internal tokenCaps;

    IBoldToken public boldToken;
    ISequencerSentinel sequencerSentinel;

    uint256 public baseRate;

    // The timestamp of the latest fee operation (redemption or new Bold issuance)
    uint256 public lastFeeOperationTime;

    event BaseRateUpdated(uint256 _baseRate);
    event LastFeeOpTimeUpdated(uint256 _lastFeeOpTime);
    event CollateralAdded(IERC20Metadata _token, ITroveManager _troveManager);
    event BranchCapUpdated(uint256 _index, ITroveManager _troveManager, uint256 _maxCap);
    event BranchShutdown(uint256 _index);

    error InvalidIndex(uint256 index);
    error InvalidCollateralList();
    error NumberOfCollateralsExceeded();
    error InvalidCollateral();
    error InvalidTroveManagerAddresses();
    error InvalidMaxCapUnder();

    constructor() {
        _disableInitializers();
    }

    function initialize(address _authority, IBoldToken _boldToken, ISequencerSentinel _sequencerSentinel)
        public
        initializer
    {
        __QuillUUPSUpgradeable_init(_authority);
        lastFeeOperationTime = block.timestamp;
        boldToken = _boldToken;
        sequencerSentinel = _sequencerSentinel;

        // Initialize the baseRate state variable
        baseRate = INITIAL_BASE_RATE;
        emit BaseRateUpdated(INITIAL_BASE_RATE);
    }

    struct RedemptionTotals {
        uint256 numCollaterals;
        uint256 boldSupplyAtStart;
        uint256 unbacked;
        uint256 redeemedAmount;
    }

    function redeemCollateral(uint256 _boldAmount, uint256 _maxIterationsPerCollateral, uint256 _maxFeePercentage)
        external
    {
        _requireSequencerUpAndOverGracePeriod();
        _requireValidMaxFeePercentage(_maxFeePercentage);
        _requireAmountGreaterThanZero(_boldAmount);

        RedemptionTotals memory totals;

        totals.numCollaterals = totalCollaterals;
        uint256[] memory unbackedPortions = new uint256[](totals.numCollaterals);
        uint256[] memory prices = new uint256[](totals.numCollaterals);

        // Gather and accumulate unbacked portions
        for (uint256 index = 0; index < totals.numCollaterals; index++) {
            ITroveManager troveManager = getTroveManager(index);
            (uint256 unbackedPortion, uint256 price, bool redeemable) =
                troveManager.getUnbackedPortionPriceAndRedeemability();
            prices[index] = price;
            if (redeemable) {
                totals.unbacked += unbackedPortion;
                unbackedPortions[index] = unbackedPortion;
            }
        }

        // There’s an unlikely scenario where all the normally redeemable branches (i.e. having TCR > SCR) have 0 unbacked
        // In that case, we redeem proportionally to branch size
        if (totals.unbacked == 0) {
            unbackedPortions = new uint256[](totals.numCollaterals);
            for (uint256 index = 0; index < totals.numCollaterals; index++) {
                ITroveManager troveManager = getTroveManager(index);
                (,, bool redeemable) = troveManager.getUnbackedPortionPriceAndRedeemability();
                if (redeemable) {
                    uint256 unbackedPortion = troveManager.getEntireBranchDebt();
                    totals.unbacked += unbackedPortion;
                    unbackedPortions[index] = unbackedPortion;
                }
            }
        } else {
            // Don't allow redeeming more than the total unbacked in one go, as that would result in a disproportionate
            // redemption (see CS-BOLD-013). Instead, truncate the redemption to total unbacked. If this happens, the
            // redeemer can call `redeemCollateral()` a second time to redeem the remainder of their BOLD.
            if (_boldAmount > totals.unbacked) {
                _boldAmount = totals.unbacked;
            }
        }

        totals.boldSupplyAtStart = boldToken.totalSupply();
        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total Bold supply value, from before it was reduced by the redemption.
        // We only compute it here, and update it at the end,
        // because the final redeemed amount may be less than the requested amount
        // Redeemers should take this into account in order to request the optimal amount to not overpay
        uint256 redemptionRate =
            _calcRedemptionRate(_getUpdatedBaseRateFromRedemption(_boldAmount, totals.boldSupplyAtStart));
        require(redemptionRate <= _maxFeePercentage, "CR: Fee exceeded provided maximum");
        // Implicit by the above and the _requireValidMaxFeePercentage checks
        //require(newBaseRate < DECIMAL_PRECISION, "CR: Fee would eat up all collateral");

        // Compute redemption amount for each collateral and redeem against the corresponding TroveManager
        for (uint256 index = 0; index < totals.numCollaterals; index++) {
            //uint256 unbackedPortion = unbackedPortions[index];
            if (unbackedPortions[index] > 0) {
                uint256 redeemAmount = _boldAmount * unbackedPortions[index] / totals.unbacked;
                if (redeemAmount > 0) {
                    ITroveManager troveManager = getTroveManager(index);
                    uint256 redeemedAmount = troveManager.redeemCollateral(
                        msg.sender, redeemAmount, prices[index], redemptionRate, _maxIterationsPerCollateral
                    );
                    totals.redeemedAmount += redeemedAmount;
                }

                // Ensure that per-branch redeems add up to `_boldAmount` exactly
                _boldAmount -= redeemAmount;
                totals.unbacked -= unbackedPortions[index];
            }
        }

        _updateBaseRateAndGetRedemptionRate(totals.redeemedAmount, totals.boldSupplyAtStart);

        // Burn the total Bold that is cancelled with debt
        if (totals.redeemedAmount > 0) {
            boldToken.burn(msg.sender, totals.redeemedAmount);
        }
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint256 minutesPassed = _minutesPassedSinceLastFeeOp();

        if (minutesPassed > 0) {
            lastFeeOperationTime += ONE_MINUTE * minutesPassed;
            emit LastFeeOpTimeUpdated(lastFeeOperationTime);
        }
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint256) {
        return (block.timestamp - lastFeeOperationTime) / ONE_MINUTE;
    }

    // Updates the `baseRate` state with math from `_getUpdatedBaseRateFromRedemption`
    function _updateBaseRateAndGetRedemptionRate(uint256 _boldAmount, uint256 _totalBoldSupplyAtStart) internal {
        uint256 newBaseRate = _getUpdatedBaseRateFromRedemption(_boldAmount, _totalBoldSupplyAtStart);

        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in `_getUpdatedBaseRateFromRedemption`

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();
    }

    /*
     * This function calculates the new baseRate in the following way:
     * 1) decays the baseRate based on time passed since last redemption or Bold borrowing operation.
     * then,
     * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
     */
    function _getUpdatedBaseRateFromRedemption(uint256 _redeemAmount, uint256 _totalBoldSupply)
        internal
        view
        returns (uint256)
    {
        // decay the base rate
        uint256 decayedBaseRate = _calcDecayedBaseRate();

        // get the fraction of total supply that was redeemed
        uint256 redeemedBoldFraction = _redeemAmount * DECIMAL_PRECISION / _totalBoldSupply;

        uint256 newBaseRate = decayedBaseRate + redeemedBoldFraction / REDEMPTION_BETA;
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

        return newBaseRate;
    }

    function _calcDecayedBaseRate() internal view returns (uint256) {
        uint256 minutesPassed = _minutesPassedSinceLastFeeOp();
        uint256 decayFactor = LiquityMath._decPow(REDEMPTION_MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / DECIMAL_PRECISION;
    }

    function _calcRedemptionRate(uint256 _baseRate) internal pure returns (uint256) {
        return LiquityMath._min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function _calcRedemptionFee(uint256 _redemptionRate, uint256 _amount) internal pure returns (uint256) {
        uint256 redemptionFee = _redemptionRate * _amount / DECIMAL_PRECISION;
        return redemptionFee;
    }

    // external redemption rate/fee getters

    function getRedemptionRate() external view override returns (uint256) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint256) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function getRedemptionRateForRedeemedAmount(uint256 _redeemAmount) external view returns (uint256) {
        uint256 totalBoldSupply = boldToken.totalSupply();
        uint256 newBaseRate = _getUpdatedBaseRateFromRedemption(_redeemAmount, totalBoldSupply);
        return _calcRedemptionRate(newBaseRate);
    }

    function getRedemptionFeeWithDecay(uint256 _ETHDrawn) external view override returns (uint256) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _ETHDrawn);
    }

    function getEffectiveRedemptionFeeInBold(uint256 _redeemAmount) external view override returns (uint256) {
        uint256 totalBoldSupply = boldToken.totalSupply();
        uint256 newBaseRate = _getUpdatedBaseRateFromRedemption(_redeemAmount, totalBoldSupply);
        return _calcRedemptionFee(_calcRedemptionRate(newBaseRate), _redeemAmount);
    }

    // getters

    function getToken(uint256 _index) external view returns (IERC20Metadata) {
        if (_index < totalCollaterals) return tokens[_index];
        else revert InvalidIndex(_index);
    }

    function getTokenCap(uint256 _index) public view returns (uint256) {
        if (_index < totalCollaterals) return tokenCaps[_index];
        else revert InvalidIndex(_index);
    }

    function getTokenCapByAddress(address _troveManagerAddress) public view returns (uint256) {
        for (uint256 i = 0; i < troveManagers.length; i++) {
            if (address(troveManagers[i]) == _troveManagerAddress) {
                return tokenCaps[i];
            }
        }

        revert("CollateralRegistry: TroveManager not found");
    }

    function getBranchCount() external view returns (uint256 branchCount) {
        return troveManagers.length;
    }

    function getTroveManager(uint256 _index) public view returns (ITroveManager) {
        if (_index < totalCollaterals) return troveManagers[_index];
        else revert InvalidIndex(_index);
    }

    function getBorrowerOperations(uint256 _index) public view returns (IBorrowerOperations) {
        return IBorrowerOperations(getTroveManager(_index).getBorrowerOperations());
    }

    // require functions

    function _requireValidMaxFeePercentage(uint256 _maxFeePercentage) internal pure {
        require(
            _maxFeePercentage >= REDEMPTION_FEE_FLOOR && _maxFeePercentage <= DECIMAL_PRECISION,
            "Max fee percentage must be between 0.5% and 100%"
        );
    }

    function _requireAmountGreaterThanZero(uint256 _amount) internal pure {
        require(_amount > 0, "CollateralRegistry: Amount must be greater than zero");
    }

    // Cuurently checks if sequencer is up and over a grace period
    // If not, does not allow the current action (reverts)
    function _requireSequencerUpAndOverGracePeriod() internal view {
        sequencerSentinel.requireUpAndOverGracePeriod();
    }

    // Privileged functions
    function addCollateral(IERC20Metadata _token, ITroveManager _troveManager, uint256 _maxCap) external restricted {
        if (totalCollaterals == MAX_NUMBER_COLLATERALS) revert NumberOfCollateralsExceeded();
        if (address(_token) == address(boldToken)) revert InvalidCollateral();
        if (_maxCap < MINIMUM_MAX_CAP_PER_BRANCH) revert InvalidMaxCapUnder();

        for (uint8 i = 0; i < troveManagers.length; i++) {
            if (address(_troveManager) == address(troveManagers[i])) {
                revert InvalidTroveManagerAddresses();
            }
        }

        uint256 collIndex = tokens.length;
        tokens.push(_token);
        troveManagers.push(_troveManager);
        tokenCaps.push(_maxCap);
        totalCollaterals++;

        boldToken.setBranchAddresses(
            collIndex,
            address(_token),
            address(_troveManager),
            address(_troveManager.stabilityPool()),
            address(_troveManager.borrowerOperations()),
            address(_troveManager.activePool())
        );

        emit CollateralAdded(_token, _troveManager);
        emit BranchCapUpdated(collIndex, _troveManager, _maxCap);
    }

    function shutdownBranch(uint256 _index) external restricted {
        getBorrowerOperations(_index).shutdownFromOracleFailureOrGovernance();
        emit BranchShutdown(_index);
    }

    // TODO: add requirements to prevent misuse/ misconfiguration
    // Issue URL: https://github.com/subvisual/quill/issues/110
    // Stuff like:
    // - Enforce SCR =< MCR < CCR after changes.
    // also highly relevant: https://github.com/liquity/bold/issues/496
    function setTroveCCR(uint256 _index, uint256 _newValue) external restricted {
        ITroveManager troveManager = getTroveManager(_index);
        troveManager.setNewBranchConfiguration(
            troveManager.SCR(),
            troveManager.MCR(),
            _newValue,
            troveManager.BCR(),
            troveManager.liquidationPenaltySP(),
            troveManager.liquidationPenaltyRedistribution(),
            troveManager.minAnnualInterestRate()
        );
    }

    function setTroveMCR(uint256 _index, uint256 _newValue) external restricted {
        ITroveManager troveManager = getTroveManager(_index);
        troveManager.setNewBranchConfiguration(
            troveManager.SCR(),
            _newValue,
            troveManager.CCR(),
            troveManager.BCR(),
            troveManager.liquidationPenaltySP(),
            troveManager.liquidationPenaltyRedistribution(),
            troveManager.minAnnualInterestRate()
        );
    }

    function setTroveSCR(uint256 _index, uint256 _newValue) external restricted {
        ITroveManager troveManager = getTroveManager(_index);
        troveManager.setNewBranchConfiguration(
            _newValue,
            troveManager.MCR(),
            troveManager.CCR(),
            troveManager.BCR(),
            troveManager.liquidationPenaltySP(),
            troveManager.liquidationPenaltyRedistribution(),
            troveManager.minAnnualInterestRate()
        );
    }

    function decreaseMinAnnualInterestRate(uint256 _index, uint256 _newValue) external restricted {
        ITroveManager troveManager = getTroveManager(_index);
        troveManager.setNewBranchConfiguration(
            troveManager.SCR(),
            troveManager.MCR(),
            troveManager.CCR(),
            troveManager.BCR(),
            troveManager.liquidationPenaltySP(),
            troveManager.liquidationPenaltyRedistribution(),
            _newValue
        );
    }

    function setSPYieldSplit(uint256 _index, uint256 _newValue) external restricted {
        ITroveManager troveManager = getTroveManager(_index);
        IActivePool activePool = troveManager.activePool();
        activePool.mintAggInterest();
        activePool.setSPYieldSplit(_newValue);
    }

    function setInterestRouter(uint256 _index, address _newInterestRouter) external restricted {
        ITroveManager troveManager = getTroveManager(_index);
        IActivePool activePool = troveManager.activePool();
        activePool.setInterestRouter(_newInterestRouter);
    }

    function setTokenCap(uint256 _index, uint256 _newValue) external restricted {
        if (_newValue < MINIMUM_MAX_CAP_PER_BRANCH) {
            revert InvalidMaxCapUnder();
        }
        tokenCaps[_index] = _newValue;

        emit BranchCapUpdated(_index, getTroveManager(_index), _newValue);
    }
}
