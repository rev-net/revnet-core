// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {JBOwnable} from "lib/juice-ownable/src/JBOwnable.sol";
import {IJBPayHook} from "lib/juice-contracts-v4/src/interfaces/IJBPayHook.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {IJB721TiersHookDeployer} from "lib/juice-721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHook} from "lib/juice-721-hook/src/interfaces/IJB721TiersHook.sol";

import {REVDeploy721TiersHookConfig} from "./structs/REVDeploy721TiersHookConfig.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVPayHookDeployer} from "./REVPayHookDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s.
contract REVTiered721HookDeployer is REVPayHookDeployer {
    /// @notice The contract responsible for deploying the tiered 721 hook.
    IJB721TiersHookDeployer public immutable HOOK_DEPLOYER;

    /// @param controller The controller that revnets are made from.
    /// @param hookDeployer The 721 tiers hook deployer.
    constructor(IJBController controller, IJB721TiersHookDeployer hookDeployer) REVPayHookDeployer(controller) {
        HOOK_DEPLOYER = hookDeployer;
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
    /// @return revnetId The ID of the newly created revnet.
    function deployTiered721RevnetFor(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVDeploy721TiersHookConfig memory hookConfiguration,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Get the revnet ID, optimistically knowing it will be one greater than the current count.
        revnetId = CONTROLLER.PROJECTS().count() + 1;

        // Keep a reference to the number of pay hooks passed in.
        uint256 numberOfOtherPayHooks = otherPayHooksSpecifications.length;

        // Track an updated list of pay hooks that'll also fit the tiered 721 hook.
        JBPayHookSpecification[] memory payHookSpecifications = new JBPayHookSpecification[](numberOfOtherPayHooks + 1);

        // Repopulate the updated list with the params passed in.
        for (uint256 i; i < numberOfOtherPayHooks; i++) {
            payHookSpecifications[i] = otherPayHooksSpecifications[i];
        }

        // Deploy the tiered 721 hook contract.
        IJB721TiersHook hook = HOOK_DEPLOYER.deployHookFor(revnetId, hookConfiguration.baselineConfig);

        // Transfer the hook's ownership to the address that called this function.
        if (hookConfiguration.customOwner != address(0)) JBOwnable(address(hook)).transferOwnership(hookConfiguration.customOwner);

        // Add the tiered 721 hook at the end.
        payHookSpecifications[numberOfOtherPayHooks] =
            JBPayHookSpecification({hook: IJBPayHook(address(hook)), amount: 0, metadata: bytes("")});

        super.deployPayHookRevnetWith({
            name: name,
            symbol: symbol,
            metadata: metadata,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            payHookSpecifications: payHookSpecifications,
            extraHookMetadata: extraHookMetadata
        });
    }
}
