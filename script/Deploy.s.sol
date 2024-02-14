// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {CTPublisher} from "@croptop/core/src/CTPublisher.sol";

import {REVBasicDeployer} from "./../src/REVBasicDeployer.sol";
import {REVCroptopDeployer} from "./../src/REVCroptopDeployer.sol";

contract Deploy is Script {
    function run() public {
        uint256 chainId = block.chainid;
        string memory chain;
        // Ethereun Mainnet
        if (chainId == 1) {
            chain = "1";
            // Ethereum Sepolia
        } else if (chainId == 11_155_111) {
            chain = "11155111";
            // Optimism Mainnet
        } else if (chainId == 420) {
            chain = "420";
            // Optimism Sepolia
        } else if (chainId == 11_155_420) {
            chain = "11155420";
            // Polygon Mainnet
        } else if (chainId == 137) {
            chain = "137";
            // Polygon Mumbai
        } else if (chainId == 80_001) {
            chain = "80001";
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        address controllerAddress = _getDeploymentAddress(
            string.concat("node_modules/@bananapus/core/broadcast/Deploy.s.sol/", chain, "/run-latest.json"), "JBController"
        );

        address hookDeployerAddress = _getDeploymentAddress(
            string.concat("node_modules/@bananapus/721-hook/broadcast/Deploy.s.sol/", chain, "/run-latest.json"),
            "JB721TiersHookDeployer"
        );

        address croptopPublisherAddress = _getDeploymentAddress(
            string.concat("node_modules/@bananapus/core/broadcast/Deploy.s.sol/", chain, "/run-latest.json"),
            "CroptopPublisher"
        );

        vm.startBroadcast();
        new REVBasicDeployer(IJBController(controllerAddress), address(0));
        new REVCroptopDeployer(
            IJBController(controllerAddress),
            address(0),
            IJB721TiersHookDeployer(hookDeployerAddress),
            CTPublisher(croptopPublisherAddress)
        );
        vm.stopBroadcast();
    }

    /// @notice Get the address of a contract that was deployed by the Deploy script.
    /// @dev Reverts if the contract was not found.
    /// @param path The path to the deployment file.
    /// @param contractName The name of the contract to get the address of.
    /// @return The address of the contract.
    function _getDeploymentAddress(string memory path, string memory contractName) internal view returns (address) {
        string memory deploymentJson = vm.readFile(path);
        uint256 nOfTransactions = stdJson.readStringArray(deploymentJson, ".transactions").length;

        for (uint256 i = 0; i < nOfTransactions; i++) {
            string memory currentKey = string.concat(".transactions", "[", Strings.toString(i), "]");
            string memory currentContractName =
                stdJson.readString(deploymentJson, string.concat(currentKey, ".contractName"));

            if (keccak256(abi.encodePacked(currentContractName)) == keccak256(abi.encodePacked(contractName))) {
                return stdJson.readAddress(deploymentJson, string.concat(currentKey, ".contractAddress"));
            }
        }

        revert(string.concat("Could not find contract with name '", contractName, "' in deployment file '", path, "'"));
    }
}
