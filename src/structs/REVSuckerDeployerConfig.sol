// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "@bananapus/suckers/src/interfaces/IBPSuckerDeployer.sol";
import {BPTokenConfig} from "@bananapus/suckers/src/structs/BPTokenConfig.sol";

/// @custom:member deployer The address to deploy a sucker from for a particular chain pair.
/// @custom:member tokenConfigurations Information about how the chains will connect.
/// @custom:member shouldDeployProject A flag indicating if a revnet should be deployed on the other chain for the sucker.
struct REVSuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    BPTokenConfig[] tokenConfigurations;
    bool deployProject
}
