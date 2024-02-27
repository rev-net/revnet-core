// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {IBPSuckerRegistry} from "@bananapus/suckers/src/interfaces/IBPSuckerRegistry.sol";

import {REVDescription} from "./structs/REVDescription.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";
import {REVBasicDeployer} from "./REVBasicDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
contract REVPayHookDeployer is REVBasicDeployer {
    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    constructor(
        IJBController controller,
        IBPSuckerRegistry suckerRegistry
    )
        REVBasicDeployer(controller, suckerRegistry)
    {}

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Deploy a basic revnet that also calls other specified pay hooks.
    /// @param description The description of the revnet.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @param payHookSpecifications Any hooks that should run when the revnet is paid.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    function deployPayHookRevnetWith(
        REVDescription memory description,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet
        revnetId = _deployRevnetWith({
            description: description,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: extraHookMetadata,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });

        // Store the pay hooks.
        _storeHookSpecificationsOf(revnetId, payHookSpecifications);
    }
}
