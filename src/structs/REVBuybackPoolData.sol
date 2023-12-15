// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";

/// @custom:member token The token to setup a pool for.
/// @custom:member poolFee The fee of the pool in which swaps occur when seeking the best price for a new participant.
/// This incentivizes liquidity providers. Out of 1_000_000. A common value is 1%, or 10_000. Other passible values are
/// 0.3% and 0.1%.
/// @custom:member twapWindow The time window to take into account when quoting a price based on TWAP.
/// @custom:member twapSlippageTolerance The pricetolerance to accept when quoting a price based on TWAP.
struct REVBuybackPoolData {
    address token;
    uint24 fee;
    uint32 twapWindow;
    uint32 twapSlippageTolerance;
}
