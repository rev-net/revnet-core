// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {IJBBuybackHook} from "lib/juice-buyback-hook/src/interfaces/IJBBuybackHook.sol";

import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBasicDeployer, SuckerTokenConfig} from "./REVBasicDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
contract REVPayHookDeployer is REVBasicDeployer {

    /// @param controller The controller that revnets are made from.
    constructor(IJBController controller, address suckerDeployer) REVBasicDeployer(controller, suckerDeployer) {
    }
    
    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Deploy a basic revnet that also calls other specified pay hooks.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param projectUri The metadata URI containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param payHookSpecifications Any hooks that should run when the revnet is paid.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    function deployPayHookRevnetWith(
        string memory name,
        string memory symbol,
        string memory projectUri,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata,
        SuckerTokenConfig[] calldata suckerTokenConfig,
        bool isSucker,
        bytes32 suckerSalt
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet
        revnetId = _deployRevnetWith({
            name: name,
            symbol: symbol,
            projectUri: projectUri,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: extraHookMetadata,
            suckerTokenConfig: suckerTokenConfig,
            isSucker: isSucker,
            suckerSalt: suckerSalt
        });

        // Store the pay hooks.
        _storeHookSpecificationsOf(revnetId, payHookSpecifications);
    }
}
