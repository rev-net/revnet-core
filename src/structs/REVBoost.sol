// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member rate The percentage of newly issued tokens that should be reserved for the _boostOperator, out of
/// 10_000 (JBConstants.MAX_RESERVED_RATE).
/// @custom:member startsAtOrAfter The timestamp to start a boost at the given rate at or after.
struct REVBoost {
    uint128 rate;
    uint128 startsAtOrAfter;
}