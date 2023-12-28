// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member startsAtOrAfter The timestamp to start a stage at the given rate at or after.
/// @custom:member boostRate The percentage of newly issued tokens that should be reserved for the _boostOperator, out of
/// 10_000 (JBConstants.MAX_RESERVED_RATE).
/// @custom:member priceCeilingIncreaseFrequency The number of seconds between applied price ceiling increases. This
/// should be at least 24 hours.
/// @custom:member priceCeilingIncreasePercentage The rate at which the price ceiling should increase over time, thus
/// decreasing the rate of issuance. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_DECAY_RATE). 0% corresponds to no price ceiling increase, everyone is treated
/// equally over time.
/// @custom:member priceFloorTaxIntensity The factor determining how much each token can reclaim from the revnet once
/// redeemed.
/// This percentage is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE). 0% corresponds to no floor tax when
/// redemptions are made, everyone's redemptions are treated equally. The higher the intensity, the higher the tax.
struct REVStageConfig {
    uint40 startsAtOrAfter;
    uint16 boostRate;
    uint40 priceCeilingIncreaseFrequency;
    uint32 priceCeilingIncreasePercentage;
    uint16 priceFloorTaxIntensity;
}
