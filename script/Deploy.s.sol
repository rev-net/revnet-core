// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
import "forge-std/StdJson.sol";

// import {IJBController} from "@juice/interfaces/IJBController.sol";
// import {REVBasicDeployer} from "src/REVBasicDeployer.sol";

abstract contract Deploy is Script {
    function _chainName() internal virtual returns (string memory);
    function _run() internal {
        vm.broadcast();
        // address controllerAddress = stdJson.readAddress(
        //         vm.readFile(
        //             string.concat("lib/juice-buyback/lib/juice-contracts-v4/deployments/", _chainName() , "/run-latest.json")
        //         ),
        //         ".transactions[9].contractAddress"
        //     );
        // address controllerAddress = address(123);
        // emit k(controllerAddress);
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