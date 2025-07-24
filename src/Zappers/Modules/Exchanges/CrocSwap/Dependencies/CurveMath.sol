// SPDX-License-Identifier: GPL-3

pragma solidity ^0.8.19;

/* @title Curve and swap math library
 * @notice Library that defines locally stable constant liquidity curves and
 *         swap struct, as well as functions to derive impact and aggregate 
 *         liquidity measures on these objects. */
library CurveMath {
    
    struct CurveState {
        uint128 priceRoot_;
        uint128 ambientSeeds_;
        uint128 concLiq_;
        uint64 seedDeflator_;
        uint64 concGrowth_;
    }
    
}
