// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../../Dependencies/LiquityMath.sol";
import "./QuillPriceFeedBase.sol";

contract QuillCompositePriceFeed is QuillPriceFeedBase {
    Oracle public lstEthOracle;

    constructor(
        address _authority,
        address _lstEthOracleAddress,
        address _ethUsdOracleAddress,
        uint256 _lstEthStalenessThreshold,
        uint256 _ethUsdStalenessThreshold
    ) QuillPriceFeedBase(_authority, _ethUsdOracleAddress, _ethUsdStalenessThreshold) {
        // Store LST-ETH oracle
        lstEthOracle.aggregator = AggregatorV3Interface(_lstEthOracleAddress);
        lstEthOracle.stalenessThreshold = _lstEthStalenessThreshold;
        lstEthOracle.decimals = lstEthOracle.aggregator.decimals();

        fetchPrice();

        // Check the oracle didn't already fail
        assert(priceSource == PriceSource.primary);
    }

    // Returns:
    // - The price, using the current price calculation
    // - A bool that is true if:
    // --- a) the system was not shut down prior to this call, and
    // --- b) an oracle or exchange rate contract failed during this call.
    function fetchPrice() public returns (uint256, bool) {
        // If branch is live and the primary oracle setup has been working, try to use it
        if (priceSource == PriceSource.primary) {
            return _fetchPricePrimary(false);
        }

        return _fetchPriceDuringShutdown();
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        // If branch is live and the primary oracle setup has been working, try to use it
        if (priceSource == PriceSource.primary) return _fetchPricePrimary(true);

        return _fetchPriceDuringShutdown();
    }

    function _fetchPriceDuringShutdown() internal view returns (uint256, bool) {
        // when branch is shut down and already using the lastGoodPrice, continue with it
        assert(priceSource == PriceSource.lastGoodPrice);
        return (lastGoodPrice, false);
    }

    // An individual Pricefeed instance implements _fetchPricePrimary according to the data sources it uses. Returns:
    // - The price
    // - A bool indicating whether a new oracle failure or exchange rate failure was detected in the call
    function _fetchPricePrimary(bool /* _isRedemption */ ) internal returns (uint256, bool) {
        assert(priceSource == PriceSource.primary);
        (uint256 ethUsdPrice, bool ethUsdOracleDown) = _getOracleAnswer(ethUsdOracle);
        (uint256 lstEthPrice, bool lstEthOracleDown) = _getOracleAnswer(lstEthOracle);

        // If the ETH-USD feed is down, shut down and switch to the last good price seen by the system
        // since we need both ETH-USD and canonical for primary and fallback price calcs
        if (ethUsdOracleDown) {
            return (_shutDownAndSwitchToLastGoodPrice(address(ethUsdOracle.aggregator)), true);
        }

        if (lstEthOracleDown) {
            return (_shutDownAndSwitchToLastGoodPrice(address(lstEthOracle.aggregator)), true);
        }

        // Otherwise, use the primary price calculation:

        // Calculate the market RETH-USD price: USD_per_RETH = USD_per_ETH * ETH_per_RETH
        uint256 lstUsdPrice = (ethUsdPrice * lstEthPrice) / 1e18;

        lastGoodPrice = lstUsdPrice;
        return (lstUsdPrice, false);
    }
}
