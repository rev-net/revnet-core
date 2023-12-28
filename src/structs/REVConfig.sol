// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVStageConfig} from "./REVStageConfig.sol";

/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 unit of the base
/// currency contributed to the revnet. This should _not_ be specified as a fixed point number with 18 decimals, this
/// will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _boostOperator. This should
/// _not_ be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @param operator The address that will receive the token premint and initial boost, and who is
/// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
/// @custom:member stageConfigurations The periods of changing constraints.
struct REVConfig {
    uint32 baseCurrency;
    uint32 initialIssuanceRate;
    uint32 premintTokenAmount;
    address operator;
    REVStageConfig[] stageConfigurations;
}
