// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";

import {IREVBasic} from "./IREVBasic.sol";

interface IREVPayHook is IREVBasic {
    event StoredPayHookSpecifications(
        uint256 indexed revnetId, JBPayHookSpecification[] payHookSpecifications, address caller
    );
}
