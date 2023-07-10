// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

contract DeployMainnet is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}

contract DeployGoerli is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}
