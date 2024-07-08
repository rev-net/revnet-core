// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVStageConfig} from "./REVStageConfig.sol";
import {REVDescription} from "./REVDescription.sol";

/// @custom:member description The description of the revnet.
/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the initial operator.
/// @custom:member premintChainId The ID of the chain on which the premint should be honored.
/// @custom:member premintStage The stage during which the premint should be honored.
/// @custom:member splitOperator The address that will receive the token premint and initial production split,
/// and who
/// is
/// allowed to change who the operator is. Only the operator can replace itself after deployment.
/// @custom:member stageConfigurations The periods of changing constraints.
struct REVConfig {
    REVDescription description;
    uint32 baseCurrency;
    address splitOperator;
    REVStageConfig[] stageConfigurations;
}
