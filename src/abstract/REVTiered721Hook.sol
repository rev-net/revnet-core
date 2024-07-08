// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPayHook} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IBPSuckerRegistry} from "@bananapus/suckers/src/interfaces/IBPSuckerRegistry.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJBProjectHandles} from "@bananapus/project-handles/src/interfaces/IJBProjectHandles.sol";

import {REVPayHook} from "./REVPayHook.sol";
import {IREVTiered721Hook} from "../interfaces/IREVTiered721Hook.sol";
import {REVDeploy721TiersHookConfig} from "./../structs/REVDeploy721TiersHookConfig.sol";
import {REVConfig} from "./../structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./../structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s.
contract REVTiered721Hook is REVPayHook, IREVTiered721Hook {
    /// @notice The contract responsible for deploying the tiered 721 hook.
    IJB721TiersHookDeployer public immutable override HOOK_DEPLOYER;

    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    /// @param projectHandles The contract that stores ENS project handles.
    /// @param feeRevnetId The ID of the revnet that will receive fees.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    /// @param hookDeployer The 721 tiers hook deployer.
    constructor(
        IJBController controller,
        IBPSuckerRegistry suckerRegistry,
        IJBProjectHandles projectHandles,
        uint256 feeRevnetId,
        address trustedForwarder,
        IJB721TiersHookDeployer hookDeployer
    )
        REVPayHook(controller, suckerRegistry, projectHandles, feeRevnetId, trustedForwarder)
    {
        HOOK_DEPLOYER = hookDeployer;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
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

    function _launchTiered721RevnetFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig memory hookConfiguration,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata
    )
        internal
        returns (uint256, IJB721TiersHook hook)
    {
        // Keep a reference to the original revnet ID passed in.
        uint256 originalRevnetId = revnetId;

        // Get the revnet ID, optimistically knowing it will be one greater than the current count.
        if (revnetId == 0) revnetId = _projects().count() + 1;

        // Keep a reference to the number of pay hooks passed in.
        uint256 numberOfOtherPayHooks = otherPayHooksSpecifications.length;

        // Track an updated list of pay hooks that'll also fit the tiered 721 hook.
        JBPayHookSpecification[] memory payHookSpecifications = new JBPayHookSpecification[](numberOfOtherPayHooks + 1);

        // Repopulate the updated list with the params passed in.
        for (uint256 i; i < numberOfOtherPayHooks; i++) {
            payHookSpecifications[i] = otherPayHooksSpecifications[i];
        }

        // Deploy the tiered 721 hook contract.
        hook = HOOK_DEPLOYER.deployHookFor(revnetId, hookConfiguration.baseline721HookConfiguration);

        // If needed, give the operator permission to add and remove tiers.
        if (hookConfiguration.splitOperatorCanAdjustTiers) {
            _CUSTOM_SPLIT_OPERATOR_PERMISSIONS_INDEXES[revnetId].push(JBPermissionIds.ADJUST_721_TIERS);
        }

        // If needed, give the operator permission to set the 721's metadata.
        if (hookConfiguration.splitOperatorCanUpdateMetadata) {
            _CUSTOM_SPLIT_OPERATOR_PERMISSIONS_INDEXES[revnetId].push(JBPermissionIds.SET_721_METADATA);
        }

        // If needed, give the operator permission to mint 721's from tiers that allow it.
        if (hookConfiguration.splitOperatorCanMint) {
            _CUSTOM_SPLIT_OPERATOR_PERMISSIONS_INDEXES[revnetId].push(JBPermissionIds.MINT_721);
        }

        // Add the tiered 721 hook at the end.
        payHookSpecifications[numberOfOtherPayHooks] =
            JBPayHookSpecification({hook: IJBPayHook(address(hook)), amount: 0, metadata: bytes("")});

        _launchPayHookRevnetFor({
            revnetId: originalRevnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            payHookSpecifications: payHookSpecifications,
            extraHookMetadata: extraHookMetadata
        });

        return (revnetId, hook);
    }
}
