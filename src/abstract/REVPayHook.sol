// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {IBPSuckerRegistry} from "@bananapus/suckers/src/interfaces/IBPSuckerRegistry.sol";
import {IJBProjectHandles} from "@bananapus/project-handles/src/interfaces/IJBProjectHandles.sol";

import {REVBasic} from "./REVBasic.sol";
import {IREVPayHook} from "../interfaces/IREVPayHook.sol";
import {REVConfig} from "./../structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./../structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
abstract contract REVPayHook is REVBasic, IREVPayHook {
    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    /// @param projectHandles The contract that stores ENS project handles.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBController controller,
        IBPSuckerRegistry suckerRegistry,
        IJBProjectHandles projectHandles,
        address trustedForwarder
    )
        REVBasic(controller, suckerRegistry, projectHandles, trustedForwarder)
    {}

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Launch a basic revnet that also calls other specified pay hooks.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @param payHookSpecifications Any hooks that should run when the revnet is paid.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    function _launchPayHookRevnetFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata
    )
        internal 
        returns (uint256)
    {
        // Deploy the revnet
        revnetId = _launchRevnetFor({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: extraHookMetadata,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });

        // Store the pay hooks.
        // Keep a reference to the number of pay hooks are being stored.
        uint256 numberOfPayHookSpecifications = payHookSpecifications.length;

        // Store the pay hooks.
        for (uint256 i; i < numberOfPayHookSpecifications; i++) {
            // Store the value.
            _payHookSpecificationsOf[revnetId].push(payHookSpecifications[i]);
        }

        emit StoredPayHookSpecifications(revnetId, payHookSpecifications, _msgSender());

        return revnetId;
    }
}
