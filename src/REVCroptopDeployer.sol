// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CTPublisher} from "@croptop/core/src/CTPublisher.sol";
import {CTAllowedPost} from "@croptop/core/src/structs/CTAllowedPost.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IBPSuckerRegistry} from "@bananapus/suckers/src/interfaces/IBPSuckerRegistry.sol";

import {REVDeploy721TiersHookConfig} from "./structs/REVDeploy721TiersHookConfig.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVCroptopAllowedPost} from "./structs/REVCroptopAllowedPost.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";
import {REVTiered721HookDeployer} from "./REVTiered721HookDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s via the croptop
/// publisher.
contract REVCroptopDeployer is REVTiered721HookDeployer {
    /// @notice The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    CTPublisher public PUBLISHER;

    /// @notice The permissions that the croptop publisher should be granted. This is set once in the constructor to
    /// contain only the ADJUST_TIERS operation.
    /// @dev This should only be set in the constructor.
    uint256[] internal _CROPTOP_PERMISSIONS_INDEXES;

    /// @param controller The controller that revnets are made from.
    /// @param hookDeployer The 721 tiers hook deployer.
    /// @param publisher The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    constructor(
        IJBController controller,
        IJB721TiersHookDeployer hookDeployer,
        CTPublisher publisher,
        IBPSuckerRegistry suckerRegistry
    )
        REVTiered721HookDeployer(controller, hookDeployer, suckerRegistry)
    {
        PUBLISHER = publisher;
        _CROPTOP_PERMISSIONS_INDEXES.push(JBPermissionIds.ADJUST_721_TIERS);
    }

    /// @notice Deploy a revnet that supports 721 sales.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @param hookConfiguration Data used for setting up the 721 tiers.
    /// @param otherPayHooksSpecifications Any hooks that should run when the revnet is paid alongside the 721 hook.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @param allowedPosts The type of posts that the network should allow.
    /// @return revnetId The ID of the newly created revnet.
    /// @return hook The address of the 721 hook that was deployed on the revnet.
    function deployCroptopRevnetWith(
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig memory hookConfiguration,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata,
        REVCroptopAllowedPost[] memory allowedPosts
    )
        public
        returns (uint256 revnetId, IJB721TiersHook hook)
    {
        // Deploy the revnet with tiered 721 hooks.
        (revnetId, hook) = super.deployTiered721RevnetWith({
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            hookConfiguration: hookConfiguration,
            otherPayHooksSpecifications: otherPayHooksSpecifications,
            extraHookMetadata: extraHookMetadata,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });

        // Keep a reference to the number of allowed posts.
        uint256 numberOfAllowedPosts = allowedPosts.length;

        // Keep a reference to the formatted allowed posts.
        CTAllowedPost[] memory formattedAllowedPosts = new CTAllowedPost[](numberOfAllowedPosts);

        // Keep a reference to the post being iterated on.
        REVCroptopAllowedPost memory post;

        // Specify the hook for each allowed post.
        for (uint256 i; i < numberOfAllowedPosts; i++) {
            // Set the post being iterated on.
            post = allowedPosts[i];

            // Set the formated post. 
            formattedAllowedPosts[i] = CTAllowedPost({
                nft: address(hook),
                category: post.category,
                minimumPrice: post.minimumPrice,
                minimumTotalSupply: post.minimumTotalSupply,
                maximumTotalSupply: post.maximumTotalSupply,
                allowedAddresses: post.allowedAddresses
            });
        }

        // Configure allowed posts.
        if (allowedPosts.length != 0) {
            PUBLISHER.configurePostingCriteriaFor({ projectId: revnetId, allowedPosts: formattedAllowedPosts});
        }

        // Give the croptop publisher permission to post on this contract's behalf.
        IJBPermissioned(address(CONTROLLER)).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: address(PUBLISHER),
                projectId: revnetId,
                permissionIds: _CROPTOP_PERMISSIONS_INDEXES
            })
        });
    }
}
