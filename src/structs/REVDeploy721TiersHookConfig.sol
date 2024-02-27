// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";

/// @custom:member baseline721HookConfiguration The baseline config.
/// @custom:member admin An address that can adjust the tiers of the 721, the metadata, and mint from tiers if the tier allows for it.
struct REVDeploy721TiersHookConfig {
    JBDeploy721TiersHookConfig baseline721HookConfiguration;
    address admin;
}
