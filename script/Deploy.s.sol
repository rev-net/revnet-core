// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "@bananapus/project-handles/script/helpers/ProjectHandlesDeploymentLib.sol";
import "@croptop/core/script/helpers/CroptopDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {REVBasicDeployer} from "./../src/REVBasicDeployer.sol";
import {REVCroptopDeployer} from "./../src/REVCroptopDeployer.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;
    /// @notice tracks the deployment of the croptop contracts for the chain we are deploying to.
    CroptopDeployment croptop;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deploymet of the project handles contracts for the chain we are deploying to.
    ProjectHandlesDeployment projectHandles;

    /// @notice The address that is allowed to forward calls to the terminal and controller on a users behalf.
    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 BASIC_DEPLOYER = "REVBasicDeployer";
    bytes32 CROPTOP_DEPLOYER = "REVCroptopDeployer";

    function configureSphinx() public override {
        // TODO: Update to contain revnet devs.
        sphinxConfig.projectName = "revnet-core-testnet";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        // Get the deployment addresses for the suckers contracts for this chain.
        suckers = SuckerDeploymentLib.getDeployment(
            vm.envOr("NANA_SUCKERS_DEPLOYMENT_PATH", string("node_modules/@bananapus/suckers/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        croptop = CroptopDeploymentLib.getDeployment(
            vm.envOr("CROPTOP_CORE_DEPLOYMENT_PATH", string("node_modules/@croptop/core/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        hook = Hook721DeploymentLib.getDeployment(
            vm.envOr("NANA_721_DEPLOYMENT_PATH", string("node_modules/@bananapus/721-hook/deployments/"))
        );
        // Get the deployment addresses for the project handles contracts for this chain.
        projectHandles = ProjectHandlesDeploymentLib.getDeployment(
            vm.envOr(
                "NANA_PROJECT_HANDLES_DEPLOYMENT_PATH", string("node_modules/@bananapus/project-handles/deployments/")
            )
        );
        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        // TODO deploy a new project to collect fees through iff needed. remove hardcoded 2.
        uint256 FEE_PROJECT_ID = 2;

        // Check if the contracts are already deployed or if there are any changes.
        if (
            !_isDeployed(
                BASIC_DEPLOYER,
                type(REVBasicDeployer).creationCode,
                abi.encode(
                    core.controller, suckers.registry, projectHandles.project_handles, FEE_PROJECT_ID, TRUSTED_FORWARDER
                )
            )
        ) {
            new REVBasicDeployer{salt: BASIC_DEPLOYER}(
                core.controller, suckers.registry, projectHandles.project_handles, FEE_PROJECT_ID, TRUSTED_FORWARDER
            );
        }

        if (
            !_isDeployed(
                CROPTOP_DEPLOYER,
                type(REVCroptopDeployer).creationCode,
                abi.encode(
                    core.controller,
                    suckers.registry,
                    projectHandles.project_handles,
                    FEE_PROJECT_ID,
                    TRUSTED_FORWARDER,
                    hook.hook_deployer,
                    croptop.publisher
                )
            )
        ) {
            new REVCroptopDeployer{salt: CROPTOP_DEPLOYER}(
                core.controller,
                suckers.registry,
                projectHandles.project_handles,
                FEE_PROJECT_ID,
                TRUSTED_FORWARDER,
                hook.hook_deployer,
                croptop.publisher
            );
        }
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return address(_deployedTo).code.length != 0;
    }
}
