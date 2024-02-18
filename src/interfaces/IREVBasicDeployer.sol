pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";
import {REVDescription} from "../structs/REVDescription.sol";
import {REVConfig} from "../structs/REVConfig.sol";

interface IREVBasicDeployer {
    function deployRevnetWith(
        REVDescription memory description,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external
        returns (uint256 revnetId);

    function deploySuckersFor(
        uint256 projectId,
        bytes memory encodedConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external;
}
