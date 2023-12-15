// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";

import {
    IJBController,
    IJBMultiTerminal,
    BasicRevnetDeployer,
    IJBBuybackHook
} from "./../src/BasicRevnetDeployer.sol";

contract Deploy is Script {
    function _run(IJBController controller) internal {
        vm.broadcast();
        new BasicRevnetDeployer(controller);
    }
}

contract DeployMainnet is Deploy {
    function setUp() public { }

    function run() public {
        _run({ controller: IJBController(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b) });
    }
}

contract DeployGoerli is Deploy {
    function setUp() public { }

    function run() public {
        _run({ controller: IJBController(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6) });
    }
}
