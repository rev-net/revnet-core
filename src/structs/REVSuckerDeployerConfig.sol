// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "@bananapus/suckers/src/interfaces/IBPSuckerDeployer.sol";
import {BPTokenMapping} from "@bananapus/suckers/src/structs/BPTokenMapping.sol";

/// @custom:member deployer The address to deploy a sucker from for a particular chain pair.
/// @custom:member tokenMappings Information about how the chains will connect.
struct REVSuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    BPTokenMapping[] tokenMappings;
}
