// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVBoostConfig} from "./REVBoostConfig.sol";

/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 unit of the base
/// currency contributed to the revnet. This should _not_ be specified as a fixed point number with 18 decimals, this
/// will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _boostOperator. This should
/// _not_
/// be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member boostConfigs The periods of distinguished boosting that should be applied over time.
struct REVConfig {
    uint256 baseCurrency;
    uint256 initialIssuanceRate;
    uint256 premintTokenAmount;
    REVBoostConfig[] boostConfigs;
}
