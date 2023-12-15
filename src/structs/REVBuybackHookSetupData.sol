// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {REVBuybackPoolData} from './REVBuybackPoolData.sol';

/// @custom:member hook The buyback hook to use.
/// @custom:member pools The pools to setup on the given buyback contract.
struct REVBuybackHookSetupData {
    IJBBuybackHook hook;
    REVBuybackPoolData[] pools;
}