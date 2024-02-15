// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "@bananapus/suckers/src/interfaces/IBPSuckerDeployer.sol";
import {BPTokenConfig} from "@bananapus/suckers/src/structs/BPTokenConfig.sol";

struct REVSuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    BPTokenConfig[] tokenConfigurations;
}
