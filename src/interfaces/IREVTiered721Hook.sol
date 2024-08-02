// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";

import {IREVPayHook} from "./IREVPayHook.sol";

interface IREVTiered721Hook is IREVPayHook {
    function HOOK_DEPLOYER() external view returns (IJB721TiersHookDeployer);
}
