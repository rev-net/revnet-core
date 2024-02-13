// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBBuybackHook} from "lib/juice-buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {REVBuybackPoolConfig} from "./REVBuybackPoolConfig.sol";

/// @custom:member hook The buyback hook to use.
/// @custom:member poolConfigurations The pools to setup on the given buyback contract.
struct REVBuybackHookConfig {
    IJBBuybackHook hook;
    REVBuybackPoolConfig[] poolConfigurations;
}
