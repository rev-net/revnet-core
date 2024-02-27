// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";

/// @custom:member baseline721HookConfiguration The baseline config.
/// @custom:member operatorCanAdjustTiers A flag indicating if the operator can add tiers or remove ones that don't have flags that prevent removal.
struct REVDeploy721TiersHookConfig {
    JBDeploy721TiersHookConfig baseline721HookConfiguration;
    bool operatorCanAdjustTiers;
}
