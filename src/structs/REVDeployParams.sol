// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVBoost} from './REVBoost.sol';

/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 unit of the base
/// currency contributed to the revnet. This should _not_ be specified as a fixed point number with 18 decimals, this
/// will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _boostOperator. This should
/// _not_
/// be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member priceCeilingIncreaseFrequency The number of seconds between applied price ceiling increases. This
/// should be at least
/// 24 hours.
/// @custom:member priceCeilingIncreasePercentage The rate at which the price ceiling should increase over time, thus
/// decreasing the rate of issuance. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_DISCOUNT_RATE). 0% corresponds to no price ceiling increase, everyone is treated
/// equally over time.
/// @custom:member priceFloorTaxIntensity The factor determining how much each token can reclaim from the revnet once
/// redeemed.
/// This percentage is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE). 0% corresponds to no floor tax when
/// redemptions are made, everyone's redemptions are treated equally. The higher the intensity, the higher the tax.
/// @custom:member boosts The periods of distinguished boosting that should be applied over time.
struct REVDeployParams {
    uint256 baseCurrency;
    uint256 initialIssuanceRate;
    uint256 premintTokenAmount;
    uint256 priceCeilingIncreaseFrequency;
    uint256 priceCeilingIncreasePercentage;
    uint256 priceFloorTaxIntensity;
    REVBoost[] boosts;
}
