// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {REVBuybackPoolConfig} from "./REVBuybackPoolConfig.sol";

/// @custom:member hook The buyback hook to use.
/// @custom:member poolConfigs The pools to setup on the given buyback contract.
struct REVBuybackHookConfig {
    IJBBuybackHook hook;
    REVBuybackPoolConfig[] poolConfigs;
}
