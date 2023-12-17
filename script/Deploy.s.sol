// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";
// import "forge-std/StdJson.sol";

import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {REVBasicDeployer} from "src/REVBasicDeployer.sol";

contract Deploy is Script {
    function run() public {
        uint256 chainId = block.chainid;
        address controllerAddress;

        // Ethereun Mainnet
        if (chainId == 1) {
            controllerAddress = address(0);
            // Ethereum Sepolia
        } else if (chainId == 11_155_111) {
            controllerAddress = 0x876437e4237017d2178022d1352A59be661C4142;
            // Optimism Mainnet
        } else if (chainId == 420) {
            controllerAddress = address(0);
            // Optimism Sepolia
        } else if (chainId == 11_155_420) {
            controllerAddress = 0x0227b76E082c635887ec58BaCaabAcC86934fe1c;
            // Polygon Mainnet
        // } else if (chainId == 137) {
        //     // Polygon Mumbai
        // } else if (chainId == 80_001) {
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        // address controllerAddress = address(123);
        // emit k(controllerAddress);
        vm.broadcast();
        new REVBasicDeployer(IJBController(controllerAddress));
    }
}