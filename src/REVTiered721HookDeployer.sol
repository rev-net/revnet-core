// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";

import {REVTiered721Hook} from "./abstract/REVTiered721Hook.sol";
import {IREVTiered721HookDeployer} from "./interfaces/IREVTiered721HookDeployer.sol";
import {REVDeploy721TiersHookConfig} from "./structs/REVDeploy721TiersHookConfig.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s.
contract REVTiered721HookDeployer is REVTiered721Hook, IREVTiered721HookDeployer {
    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    /// @param feeRevnetId The ID of the revnet that will receive fees.
    /// @param hookDeployer The 721 tiers hook deployer.
    constructor(
        IJBController controller,
        IJBSuckerRegistry suckerRegistry,
        uint256 feeRevnetId,
        IJB721TiersHookDeployer hookDeployer
    )
        REVTiered721Hook(controller, suckerRegistry, feeRevnetId, hookDeployer)
    {}

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Launch a revnet that supports 721 sales.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @param hookConfiguration Data used for setting up the 721 tiers.
    /// @param otherPayHooksSpecifications Any hooks that should run when the revnet is paid alongside the 721 hook.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    /// @return hook The address of the 721 hook that was deployed on the revnet.

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
        override
        returns (uint256, IJB721TiersHook hook)
    {
        (revnetId, hook) = _launchTiered721RevnetFor({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            hookConfiguration: hookConfiguration,
            otherPayHooksSpecifications: otherPayHooksSpecifications,
            extraHookMetadata: extraHookMetadata
        });

        return (revnetId, hook);
    }
}
