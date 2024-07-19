// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {IJBProjectHandles} from "@bananapus/project-handles/src/interfaces/IJBProjectHandles.sol";

import {REVBasic} from "./abstract/REVBasic.sol";
import {IREVBasicDeployer} from "./interfaces/IREVBasicDeployer.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic Revnet.
contract REVBasicDeployer is REVBasic, IREVBasicDeployer {
    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    /// @param projectHandles The contract that stores ENS project handles.
    /// @param feeRevnetId The ID of the revnet that will receive fees.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBController controller,
        IJBSuckerRegistry suckerRegistry,
        IJBProjectHandles projectHandles,
        uint256 feeRevnetId,
        address trustedForwarder
    )
        REVBasic(controller, suckerRegistry, projectHandles, feeRevnetId, trustedForwarder)
    {}

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Launch a basic revnet.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @return revnetId The ID of the newly created revnet.
    function deployFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external
        override
        returns (uint256)
    {
        // Deploy main revnet.
        return _launchRevnetFor({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: 0,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });
    }
}
