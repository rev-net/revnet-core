// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
// import "forge-std/StdJson.sol";

import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {REVBasicDeployer} from "src/REVBasicDeployer.sol";

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

        address controllerAddress = 
            stdJson.readAddress(
            vm.readFile(
                string.concat(
                    "lib/juice-contracts-v4/broadcast/Deploy.s.sol/", chain, "/run-latest.json"
                )
            ),
            ".transactions[7].contractAddress"
        );

        vm.broadcast();
        new REVBasicDeployer(IJBController(controllerAddress));
    }
}