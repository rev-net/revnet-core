// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";

import {REVAutoIssuance} from "./REVAutoIssuance.sol";

/// @custom:member startsAtOrAfter The timestamp to start a stage at the given rate at or after.
/// @custom:member autoIssuances The configurations of mints during this stage.
/// @custom:member splitPercent The percentage of newly issued tokens that should be split with the operator, out
/// of 10_000 (JBConstants.MAX_RESERVED_PERCENT).
/// @custom:member splits The splits for the revnet.
/// @custom:member initialIssuance The number of revnet tokens that one unit of the revnet's base currency will buy, as
/// a fixed point number
/// with 18 decimals.
/// @custom:member issuanceCutFrequency The number of seconds between applied issuance decreases. This
/// should be at least 24 hours.
/// @custom:member issuanceCutPercent The percent that issuance should decrease over time. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_CUT_PERCENT). 0% corresponds to no issuance increase.
/// @custom:member cashOutTaxRate The factor determining how much each token can cash out from the revnet once
/// cashed out. This rate is out of 10_000 (JBConstants.MAX_CASH_OUT_TAX_RATE). 0% corresponds to no tax when cashing
/// out.
/// @custom:member extraMetadata Extra info to attach set into this stage that may affect hooks.
struct REVStageConfig {
    uint48 startsAtOrAfter;
    REVAutoIssuance[] autoIssuances;
    uint16 splitPercent;
    JBSplit[] splits;
    uint112 initialIssuance;
    uint32 issuanceCutFrequency;
    uint32 issuanceCutPercent;
    uint16 cashOutTaxRate;
    uint16 extraMetadata;
}
