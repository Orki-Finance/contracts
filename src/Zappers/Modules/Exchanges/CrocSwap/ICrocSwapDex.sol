// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DECIMAL_PRECISION} from "src/Dependencies/Constants.sol";
// import "forge-std/console.sol";

interface ICrocSwapDex {

    /* @notice Consolidated method for protocol control related commands.
     * @dev    We consolidate multiple protocol control types into a single method to 
     *         reduce the contract size in the main contract by paring down methods.
     * 
     * @param callpath The proxy sidecar callpath called into. (Calls into proxyCmd() on
     *                 the respective sidecare contract)
     * @param cmd      The arbitrary byte calldata corresponding to the command. Format
     *                 dependent on the specific callpath.
     * @param sudo     If true, indicates that the command should be called with elevated
     *                 privileges. */
    function protocolCmd (uint16 callpath, bytes calldata cmd, bool sudo) external payable;

    /* @notice Calls an arbitrary command on one of the sidecar proxy contracts at a specific
     *         index. Not all proxy slots may have a contract attached. If so, this call will
     *         fail.
     *
     * @param callpath The index of the proxy sidecar the command is being called on.
     * @param cmd The arbitrary call data the client is calling the proxy sidecar.
     * @return Arbitrary byte data (if any) returned by the command. */
    function userCmd (uint16 callpath, bytes calldata cmd) external payable 
    returns (bytes memory);

    /* @notice Calls an arbitrary command on behalf of a user from a (pre-approved) 
     *         external router contract acting as an agent on the user's behalf.
     *
     * @dev This can only be called when the underlying user has previously approved the
     *      msg.sender address as a router on its behalf.
     *
     * @param callpath The index of the proxy sidecar the command is being called on.
     * @param cmd The arbitrary call data the client is calling the proxy sidecar.
     * @param client The address of the client the router is calling on behalf of.
     * @return Arbitrary byte data (if any) returned by the command. */
    function userCmdRouter (uint16 callpath, bytes calldata cmd, address client) external 
    payable returns (bytes memory);

    /* @notice General purpose query fuction for reading arbitrary data from the dex.
     * @dev    This function is bare bones, because we're trying to keep the size 
     *         footprint of CrocSwapDex down. See SlotLocations.sol and QueryHelper.sol 
     *         for syntactic sugar around accessing/parsing specific data. */
    function readSlot (uint256 slot) external view returns (uint256 data);

    /* @notice Validation function used by external contracts to verify an address is
     *         a valid CrocSwapDex contract. */
    function acceptCrocDex() pure external returns (bool);
}

library CrocSwapDexHelper {
    // Original this was suppose to be the indexes for proxies
    // https://github.com/CrocSwap/CrocSwap-protocol/blob/7b3cedcf912692132491a4f013152f69969d008d/contracts/mixins/StorageLayout.sol#L178-L191
    // But it's mostly wrong or outdated (?). By "reverse engineering" (fuzzing usercmd), I found out some contracts that match
    // some verified deployments https://scrollscan.com/txs?a=0x478ce50d3ce95224312a3f44ade1e3ddc047ae1a&ps=100&p=1 

    // UserCmds
    uint16 constant HOT_PROXY = 1;       // 0xe1eC23F5069586cd4CDe4E693A354e7a45E12608
    uint16 constant COLD_PROXY = 3;     
    uint16 constant WARM_PATH = 128;

    // Bruteforced slots
    //   ProxyPath  1 :    0xd75A6d3222005440CB86408C3Ae7538d86541740   NOT VERIFIED ~ BYTECODE MATCHES BOOTPATH.sol
    //   ProxyPath  2 :    0xe1eC23F5069586cd4CDe4E693A354e7a45E12608
    //   ProxyPath  4 :    0xa01C4E40FE62c3FFd7152569E20a5BDAd23F171D
    //   ProxyPath  8 :    0x79Cf6E6aF136B04C145f330509AD547b0D7eF6e9
    //   ProxyPath  129 :  0xC58f7a96a3A8E82DA0747A6E1411c3A531220066
    //   ProxyPath  131 :  0xe3150C65446Dc05505ac33B51D742E9458fE0BfE   NOT VERIFIED ~ COULDN?T MATCH BYTECODE
    //   ProxyPath  132 :  0x418C68Ce5B73783abe178dB12dfEe9375D965dbb

    // https://github.com/CrocSwap/CrocSwap-protocol/blob/7b3cedcf912692132491a4f013152f69969d008d/contracts/callpaths/WarmPath.sol#L89
    uint8 constant MINT_AMBIENT_LIQ_LP = 3;
    uint8 constant MINT_AMBIENT_BASE_LP = 31;
    uint8 constant MINT_AMBIENT_QUOTE_LP = 32;

    // https://github.com/CrocSwap/CrocSwap-protocol/blob/7b3cedcf912692132491a4f013152f69969d008d/contracts/libraries/ProtocolCmd.sol#L72-L86
    uint16 constant FIXED_INITPOOL_SUBCODE = 71;

    // https://github.com/CrocSwap/CrocSwap-protocol/blob/7b3cedcf912692132491a4f013152f69969d008d/misc/constants/addrs.ts#L165-L178
    uint256 constant POOL_TYPE_INDEX = 420;

    struct SwapParams {
        address base;
        address quote;
        uint256 poolIdx;
        bool isBuy;
        bool inBaseQty;
        uint128 qty;            // The quantity of the fixed side of the swap
        uint16 tip;             // If zero the user accepts the standard swap fee rate in the pool. If non-zero the user agrees  to pay up to this swap fee rate to the pool's LPs. In standard cases this should be 0.
        uint128 limitPrice;     // https://docs.ambient.finance/developers/dex-contract-interface/swaps#note-on-limitprice
        uint128 minOut;         // Minimum (maximum) expected output (input) of the token being bought (sold). Exceeding this value will revert the transaction
        uint8 settleFlags;      // https://docs.ambient.finance/developers/type-conventions#settlement-flags
    }

    function getQuoteBaseOrder(address tokenA, address tokenB) internal pure returns (address base, address quote){
        if(tokenA < tokenB){
            base = tokenA;
            quote = tokenB;
        } else {
            base = tokenB;
            quote = tokenA;
        }
    }

    function priceInUSDq(
        uint256 priceRoot,
        address usdq,
        address coll,
        uint8 decimalsUSDq,
        uint8 decimalsColl
    ) internal pure returns (uint256) {
        bool isUSDqBase = usdq < coll;
        uint256 priceBaseQuote = (priceRoot * priceRoot);
        uint256 convertedToDec;

        // Similar approach to Q96, although this max could probably be greater
        if (priceBaseQuote > 115e39) { 
            convertedToDec = priceBaseQuote = ((priceBaseQuote >> 64) * 1e18) >> 64;
        } else {
            convertedToDec = priceBaseQuote = (priceBaseQuote * 1e18) >> 128;
        }

        uint256 finalPrice = convertedToDec;
        if (!isUSDqBase) {
            finalPrice = (1e36) / convertedToDec;
        }

        uint256 decimalsRate = 10 ** (decimalsUSDq- decimalsColl);

        return finalPrice/decimalsRate;
    } 

    // this function is specific for QUILL ORACLES, assumes answers with 18 decimals
    function invertPrice(uint256 price) internal pure returns (uint256) {
        require(price > 0, "Price cannot be zero");

        uint256 inversePrice = (DECIMAL_PRECISION * DECIMAL_PRECISION) / price;

        return inversePrice;
    }

    function sqrtPriceQ64(
        uint256 oracleAnswer,
        uint8 oracleDecimals,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) internal pure returns (uint256) {
        // Constants
        uint256 Q64 = 2**64;

        // Adjust oracle answer to 18 decimals precision
        // Scaling factor to convert oracle decimals to 18 decimals
        uint256 adjustedPrice = oracleAnswer * (10 ** (18 - oracleDecimals));

        // Adjust for base and quote token decimals
        // Scaling factor for the ratio of base to quote
        if (baseDecimals > quoteDecimals) {
            adjustedPrice *= 10 ** (baseDecimals - quoteDecimals);
        } else if (quoteDecimals > baseDecimals) {
            adjustedPrice /= 10 ** (quoteDecimals - baseDecimals);
        }

        // Calculate the square root price
        uint256 sqrtPrice = Math.sqrt(adjustedPrice);

        // Convert to Q64.64 format
        uint256 priceQ64 = (sqrtPrice * Q64) / 1e9; // Divide by 1e9 to adjust for sqrt(1e18)

        return priceQ64;
    }
}