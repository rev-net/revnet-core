// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";

import {REVDeploy721TiersHookConfig} from "../structs/REVDeploy721TiersHookConfig.sol";
import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";
import {IREVTiered721Hook} from "./IREVTiered721Hook.sol";

interface IREVTiered721HookDeployer is IREVTiered721Hook {
    function deployFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig memory hookConfiguration,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata
    )
        external
        returns (uint256, IJB721TiersHook hook);
}
