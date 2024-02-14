// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "@bananapus/suckers/src/interfaces/IBPSuckerDeployer.sol";
import {REVSuckerTokenConfig} from "./REVSuckerTokenConfig.sol";

struct REVSuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    REVSuckerTokenConfig[] tokenConfigurations;
}
