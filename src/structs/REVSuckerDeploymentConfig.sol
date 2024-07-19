// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";

/// @custom:member deployerConfigurations The information for how to suck tokens to other chains.
/// @custom:member salt The salt to use for creating suckers so that they use the same address across chains.
struct REVSuckerDeploymentConfig {
    JBSuckerDeployerConfig[] deployerConfigurations;
    bytes32 salt;
}
