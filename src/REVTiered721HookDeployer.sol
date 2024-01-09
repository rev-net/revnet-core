// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "lib/juice-contracts-v4/src/interfaces/IJBPermissioned.sol";
import {IJBRulesetDataHook} from "lib/juice-contracts-v4/src/interfaces/IJBRulesetDataHook.sol";
import {JBPermissionIds} from "lib/juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {JBBeforeRedeemRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBBeforePayRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforePayRecordedContext.sol";
import {JBRedeemHookSpecification} from "lib/juice-contracts-v4/src/structs/JBRedeemHookSpecification.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBRulesetConfig} from "lib/juice-contracts-v4/src/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {JBPermissionsData} from "lib/juice-contracts-v4/src/structs/JBPermissionsData.sol";
import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {IJBTiered721HookDeployer} from "lib/juice-721-hook/src/interfaces/IJBTiered721HookDeployer.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVPayHookDeployer} from "./REVPayHookDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s.
contract Tiered721RevnetDeployer is REVPayHookDeployer {
    /// @notice The contract responsible for deploying the tiered 721 hook.
    IJBTiered721HookDeployer public immutable TIERED_721_HOOK_DEPLOYER;

    /// @param controller The controller that revnets are made from.
    /// @param tiered721HookDeployer The tiered 721 hook deployer.
    constructor(
        IJBController controller,
        IJBTiered721HookDeployer tiered721HookDeployer
    )
        REVPayHookDeployer(controller)
    {
        TIERED_721_HOOK_DEPLOYER = tiered721HookDeployer;
    }

    /// @notice Deploy a revnet that supports 721 sales.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param metadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
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
        JBDeployTiered721DelegateData memory tiered721SetupData,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Get the revnet ID, optimistically knowing it will be one greater than the current count.
        revnetId = controller.projects().count() + 1;

        // Keep a reference to the number of pay hooks passed in.
        uint256 numberOfOtherPayHooks = otherPayHooksSpecifications.length;

        // Track an updated list of pay hooks that'll also fit the tiered 721 hook.
        JBPayHookSpecification[] memory payHooks = new JBPayHookSpecification[](numberOfOtherPayHooks + 1);

        // Repopulate the updated list with the params passed in.
        for (uint256 i; i < numberOfOtherPayHooks; i++) {
            payHooks[i] = otherPayHooksSpecifications[i];
        }

        // Deploy the tiered 721 hook contract.
        IJBTiered721Hook tiered721Hook = TIERED_721_HOOK_DEPLOYER.deployHookFor(revnetId, tiered721SetupData);

        // Add the tiered 721 hook at the end.
        payHooks[numberOfOtherPayHooks] = JBPayHookSpecification({
            delegate: IJBPayHook(address(tiered721Hook)),
            amount: 0,
            metadata: bytes("")
        });

        super.deployPayHookRevnetWith({
            name: name,
            symbol: symbol,
            metadata: metadata,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            payHooksSpecifications: payHooksSpecifications,
            extraHookMetadata: extraHookMetadata
        });
    }
}