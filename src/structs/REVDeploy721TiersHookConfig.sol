// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";

/// @custom:member baseline721HookConfiguration The baseline config.
/// @custom:member operatorCanAdjustTiers A flag indicating if the revnet's operator can add tiers and remove tiers if the tier is allowed to be removed 
/// @custom:member operatorCanUpdateMetadata A flag indicating if the revnet's operator can update the 721's metadata.
/// @custom:member operatorCanMint A flag indicating if the revnet's operator can mint 721's from tiers that allow it.
struct REVDeploy721TiersHookConfig {
    JBDeploy721TiersHookConfig baseline721HookConfiguration;
    bool operatorCanAdjustTiers;
    bool operatorCanUpdateMetadata;
    bool operatorCanMint;
}
