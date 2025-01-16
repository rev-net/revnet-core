// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IREVLoans} from "../interfaces/IREVLoans.sol";
import {REVDescription} from "./REVDescription.sol";
import {REVLoanSource} from "./REVLoanSource.sol";
import {REVStageConfig} from "./REVStageConfig.sol";

/// @custom:member description The description of the revnet.
/// @custom:member baseCurrency The currency that the issuance is based on.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the initial operator.
/// @custom:member premintChainId The ID of the chain on which the premint should be honored.
/// @custom:member premintStage The stage during which the premint should be honored.
/// @custom:member splitOperator The address that will receive the token premint and initial production split,
/// and who is allowed to change who the operator is. Only the operator can replace itself after deployment.
/// @custom:member stageConfigurations The periods of changing constraints.
/// @custom:member loanSources The sources for loans.
/// @custom:member loans The loans contract, which can mint the revnet's tokens and use the revnet's balance.
struct REVConfig {
    REVDescription description;
    uint32 baseCurrency;
    address splitOperator;
    REVStageConfig[] stageConfigurations;
    REVLoanSource[] loanSources;
    address loans;
}
