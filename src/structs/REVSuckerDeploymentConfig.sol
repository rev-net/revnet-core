// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVSuckerDeployerConfig} from "./REVSuckerDeployerConfig.sol";

struct REVSuckerDeploymentConfig {
    REVSuckerDeployerConfig[] deployerConfigurations;
    uint256 salt;
}
