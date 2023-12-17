// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Script.sol";

import {IJBController} from "@juice/interfaces/IJBController.sol";
import {REVBasicDeployer} from "../src/REVBasicDeployer.sol";

contract Deploy is Script {
    function _run(IJBController controller) internal {
        vm.broadcast();
        new REVBasicDeployer(controller);
    }
}

contract DeployMainnet is Deploy {
    IJBController controller = IJBController(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b);

    function setUp() public {}

    function run() public {
        _run({controller: controller});
    }
}

contract DeploySepolia is Deploy {
    IJBController controller = IJBController(0xE34f21f141f6Bc4d1889C7b5067892A90384C4C3);

    function setUp() public {}

    function run() public {
        _run({controller: controller});
    }
}
