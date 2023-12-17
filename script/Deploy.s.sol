// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
import "forge-std/StdJson.sol";

// import {IJBController} from "@juice/interfaces/IJBController.sol";
// import {REVBasicDeployer} from "src/REVBasicDeployer.sol";

abstract contract Deploy is Script {
    function _chainName() internal virtual returns (string memory);
    function _run() internal {
        uint256 chainId = block.chainid;
        address network;
        // Ethereun Mainnet
        if (chainId == 1) {
            network = "Ethereum";
            // Ethereum Sepolia
        } else if (chainId == 11_155_111) {
            network = "EthereumSepolia";
            // Optimism Mainnet
        } else if (chainId == 420) {
            network = "Op";
            // Optimism Sepolia
        } else if (chainId == 11_155_420) {
            network = "OpSepolia";
            // Polygon Mainnet
        // } else if (chainId == 137) {
        //     // Polygon Mumbai
        // } else if (chainId == 80_001) {
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }
        address controllerAddress = IJBController(
            stdJson.readAddress(
                vm.readFile(
                    string.concat(
                        "lib/juice-buyback/lib/juice-contracts-v4/deployments/", network, "/run-latest.json"
                    )
                ),
                ".transactions[9].contractAddress"
            )
        );

        // address controllerAddress = address(123);
        // emit k(controllerAddress);
        // vm.broadcast();
        // new REVBasicDeployer(IJBController(controllerAddress));
    }
}

// Ethereum

contract DeployEthereumMainnet is Deploy {
    function _chainName() internal virtual override returns (string memory) {
        return "Ethereum";
    }
}

contract DeployEthereumSepolia is Deploy {
    function _chainName() internal virtual override returns (string memory) {
        return "EthereumSepolia";
    }
}
// Optimism

contract DeployOptimismMainnet is Deploy {
    function _chainName() internal virtual override returns (string memory) {
        return "Op";
    }
}

contract DeployOptimismSepolia is Deploy {
    function _chainName() internal virtual override returns (string memory) {
        return "OpSepolia";
    }
}