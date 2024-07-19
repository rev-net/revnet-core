// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";

import {REVPayHook} from "./abstract/REVPayHook.sol";
import {IREVPayHookDeployer} from "./interfaces/IREVPayHookDeployer.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
contract REVPayHookDeployer is REVPayHook, IREVPayHookDeployer {
    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    /// @param feeRevnetId The ID of the revnet that will receive fees.
    constructor(
        IJBController controller,
        IJBSuckerRegistry suckerRegistry,
        uint256 feeRevnetId
    )
        REVPayHook(controller, suckerRegistry, feeRevnetId)
    {}

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
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
    function deployFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata
    )
        external
        override
        returns (uint256)
    {
        // Deploy the revnet
        return _launchPayHookRevnetFor({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            payHookSpecifications: payHookSpecifications,
            extraHookMetadata: extraHookMetadata
        });
    }
}
