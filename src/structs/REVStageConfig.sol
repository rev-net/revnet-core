// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVAutoIssuance} from "./REVAutoIssuance.sol";

/// @custom:member startsAtOrAfter The timestamp to start a stage at the given rate at or after.
/// @custom:member autoIssuance The configurations of mints during this stage.
/// @custom:member splitPercent The percentage of newly issued tokens that should be split with the operator, out
/// of
/// 10_000 (JBConstants.MAX_RESERVED_PERCENT).
/// @custom:member initialIssuance The number of revnet tokens that one unit of the revnet's base currency will buy, as
/// a fixed point number
/// with 18 decimals.
/// @custom:member issuanceDecayFrequency The number of seconds between applied issuance increases. This
/// should be at least 24 hours.
/// @custom:member issuanceDecayPercent The percent that issuance should decrease over time. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_DECAY_PERCENT). 0% corresponds to no issuance increase.
/// @custom:member cashOutTaxRate The factor determining how much each token can cash out from the revnet once
/// redeemed. This rate is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE). 0% corresponds to no tax when cashing out.
/// @custom:member extraMetadata Extra info to attach set into this stage that may affect hooks.
struct REVStageConfig {
    uint40 startsAtOrAfter;
    REVAutoIssuance[] autoIssuance;
    uint16 splitPercent;
    uint112 initialIssuance;
    uint32 issuanceDecayFrequency;
    uint32 issuanceDecayPercent;
    uint16 cashOutTaxRate;
    uint16 extraMetadata;
}
