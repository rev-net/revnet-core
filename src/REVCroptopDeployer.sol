// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CroptopPublisher, AllowedPost} from "lib/croptop-contracts/src/CroptopPublisher.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "lib/juice-contracts-v4/src/interfaces/IJBPermissioned.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBPermissionsData} from "lib/juice-contracts-v4/src/structs/JBPermissionsData.sol";
import {JB721PermissionIds} from "lib/juice-721-hook/src/libraries/JB721PermissionIds.sol";
import {IJB721TiersHookDeployer} from "lib/juice-721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {JBDeploy721TiersHookConfig} from "lib/juice-721-hook/src/structs/JBDeploy721TiersHookConfig.sol";

import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVTiered721HookDeployer} from "./REVTiered721HookDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s via the croptop
/// publisher.
contract REVCroptopDeployer is REVTiered721HookDeployer {
    /// @notice The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    CroptopPublisher public PUBLISHER;

    /// @notice The permissions that the croptop publisher should be granted. This is set once in the constructor to
    /// contain only the ADJUST_TIERS operation.
    /// @dev This should only be set in the constructor.
    uint256[] internal _CROPTOP_PERMISSIONS_INDEXES;

    /// @param controller The controller that revnets are made from.
    /// @param hookDeployer The 721 tiers hook deployer.
    /// @param publisher The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    constructor(
        IJBController controller,
        IJB721TiersHookDeployer hookDeployer,
        CroptopPublisher publisher
    )
        REVTiered721HookDeployer(controller, hookDeployer)
    {
        PUBLISHER = publisher;
        _CROPTOP_PERMISSIONS_INDEXES.push(JB721PermissionIds.ADJUST_TIERS);
    }

    /// @notice Deploy a revnet that supports 721 sales.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param metadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param hookConfiguration Data used for setting up the 721 tiers.
    /// @param otherPayHooksSpecifications Any hooks that should run when the revnet is paid alongside the 721 hook.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @param allowedPosts The type of posts that the network should allow.
    /// @return revnetId The ID of the newly created revnet.
    function deployCroptopRevnetFor(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        JBDeploy721TiersHookConfig memory hookConfiguration,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata,
        AllowedPost[] memory allowedPosts
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet with tiered 721 hooks.
        revnetId = super.deployTiered721RevnetFor({
            name: name,
            symbol: symbol,
            metadata: metadata,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            hookConfiguration: hookConfiguration,
            otherPayHooksSpecifications: otherPayHooksSpecifications,
            extraHookMetadata: extraHookMetadata
        });

        // Configure allowed posts.
        if (allowedPosts.length != 0) {
            PUBLISHER.configurePostingCriteriaFor(revnetId, allowedPosts);
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
