// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {stdJson} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {SphinxConstants, NetworkInfo} from "@sphinx-labs/contracts/SphinxConstants.sol";

import {REVBasicDeployer} from "../../src/REVBasicDeployer.sol";
import {REVTiered721HookDeployer} from "../../src/REVTiered721HookDeployer.sol";
import {REVCroptopDeployer} from "../../src/REVCroptopDeployer.sol";

struct RevnetCoreDeployment {
    REVBasicDeployer basic_deployer;
    REVTiered721HookDeployer nft_hook_deployer;
    REVCroptopDeployer croptop_deployer;
}

library RevnetCoreDeploymentLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    function getDeployment(string memory path) internal returns (RevnetCoreDeployment memory deployment) {
        // get chainId for which we need to get the deployment.
        uint256 chainId = block.chainid;

        // Deploy to get the constants.
        // TODO: get constants without deploy.
        SphinxConstants sphinxConstants = new SphinxConstants();
        NetworkInfo[] memory networks = sphinxConstants.getNetworkInfoArray();

        for (uint256 _i; _i < networks.length; _i++) {
            if (networks[_i].chainId == chainId) {
                return getDeployment(path, networks[_i].name);
            }
        }

        revert("ChainID is not (currently) supported by Sphinx.");
    }

    function getDeployment(
        string memory path,
        string memory network_name
    )
        internal
        view
        returns (RevnetCoreDeployment memory deployment)
    {
        deployment.basic_deployer =
            REVBasicDeployer(_getDeploymentAddress(path, "revnet-core-testnet", network_name, "REVBasicDeployer"));

        deployment.nft_hook_deployer =
            REVTiered721HookDeployer(_getDeploymentAddress(path, "revnet-core-testnet", network_name, "REVTiered721HookDeployer"));

        deployment.croptop_deployer =
            REVCroptopDeployer(_getDeploymentAddress(path, "revnet-core-testnet", network_name, "REVCroptopDeployer"));
    }

    /// @notice Get the address of a contract that was deployed by the Deploy script.
    /// @dev Reverts if the contract was not found.
    /// @param path The path to the deployment file.
    /// @param contractName The name of the contract to get the address of.
    /// @return The address of the contract.
    function _getDeploymentAddress(
        string memory path,
        string memory project_name,
        string memory network_name,
        string memory contractName
    )
        internal
        view
        returns (address)
    {
        string memory deploymentJson =
            vm.readFile(string.concat(path, project_name, "/", network_name, "/", contractName, ".json"));
        return stdJson.readAddress(deploymentJson, ".address");
    }
}
