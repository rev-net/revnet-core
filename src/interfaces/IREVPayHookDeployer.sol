pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";
import {IREVBasicDeployer} from "./IREVBasicDeployer.sol";

interface IREVPayHookDeployer is IREVBasicDeployer {
    event StoredPayHookSpecifications(
        uint256 indexed revnetId, JBPayHookSpecification[] payHookSpecifications, address caller
    );

    function deployPayHookRevnetWith(
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata
    )
        external
        returns (uint256);

    function launchPayHookRevnetFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata
    )
        external
        returns (uint256);
}
