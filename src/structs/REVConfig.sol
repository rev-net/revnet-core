// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVStageConfig} from "./REVStageConfig.sol";

/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the initial operator.
/// @custom:member initialOperator The address that will receive the token premint and initial production split, and who
/// is
/// allowed to change who the operator is. Only the operator can replace itself after deployment.
/// @custom:member stageConfigurations The periods of changing constraints.
struct REVConfig {
    uint32 baseCurrency;
    uint256 premintTokenAmount;
    address initialOperator;
    REVStageConfig[] stageConfigurations;
}
