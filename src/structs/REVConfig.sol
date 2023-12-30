// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVStageConfig} from "./REVStageConfig.sol";

/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _boostOperator.
/// @custom:member initialBoostOperator The address that will receive the token premint and initial boost, and who is
/// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
/// @custom:member stageConfigurations The periods of changing constraints.
struct REVConfig {
    uint32 baseCurrency;
    uint256 premintTokenAmount;
    address initialBoostOperator;
    REVStageConfig[] stageConfigurations;
}
