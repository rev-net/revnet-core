// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBDeploy721TiersHookConfig} from "lib/juice-721-hook/src/structs/JBDeploy721TiersHookConfig.sol";

/// @custom:member baselineConfig The baseline config.
/// @custom:member owner The address that'll own the 721 contract.
struct REVDeploy721TiersHookConfig {
    JBDeploy721TiersHookConfig baselineConfig;
    address customOwner;
}