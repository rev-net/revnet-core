// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";

import {IREVBasic} from "./IREVBasic.sol";
import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";

interface IREVBasicDeployer is IREVBasic {
    function deployFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external
        returns (uint256);
}
