// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {
    IJBController3_1,
    IJBPayoutRedemptionPaymentTerminal3_1_1,
    BasicRetailistJBDeployer,
    IJBGenericBuybackDelegate
} from "./../src/BasicRetailistJBDeployer.sol";

contract Deploy is Script {
    function _run(IJBController3_1 _controller, IJBGenericBuybackDelegate _buybackDelegate) internal {
        vm.broadcast();
        new BasicRetailistJBDeployer(_controller, _buybackDelegate);
    }
}

contract DeployMainnet is Deploy {
    function setUp() public { }

    function run() public {
        _run({
            _controller: IJBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b),
            _buybackDelegate: IJBGenericBuybackDelegate(0x6B700b54BBf7A93f453fFBF58Df0fE1ab2AADA08)
        });
    }
}

contract DeployGoerli is Deploy {
    function setUp() public { }

    function run() public {
        _run({
            _controller: IJBController3_1(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6),
            _buybackDelegate: IJBGenericBuybackDelegate(0x31682096474BFD6704992b7C5f993639E372900e)
        });
    }
}
