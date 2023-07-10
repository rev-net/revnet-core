// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {
    IJBController3_1,
    IJBPayoutRedemptionPaymentTerminal3_1_1,
    BasicRetailistJBDeployer
} from "./../src/BasicRetailistJBDeployer.sol";

contract Deploy is Script {
    function _run(IJBController3_1 _controller, IJBPayoutRedemptionPaymentTerminal3_1_1 _terminal) internal {
        vm.broadcast();
        new BasicRetailistJBDeployer(_controller, _terminal);
    }
}

contract DeployMainnet is Deploy {
    function setUp() public {}

    function run() public {
        _run({
            _controller: IJBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b),
            _terminal: IJBPayoutRedemptionPaymentTerminal3_1_1(0x457cD63bee88ac01f3cD4a67D5DCc921D8C0D573)
        });
    }
}

contract DeployGoerli is Deploy {
    function setUp() public {}

    function run() public {
        _run({
            _controller: IJBController3_1(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6),
            _terminal: IJBPayoutRedemptionPaymentTerminal3_1_1(0x82129d4109625F94582bDdF6101a8Cd1a27919f5)
        });
    }
}
