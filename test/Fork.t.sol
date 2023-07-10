// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";

import "../src/Empty.sol";

contract EmptyTest_Fork is Test {
    IJBController JBController;
    IJBDirectory JBDirectory;
    IJBFundingCycleStore JBFundingCycleStore;
    IJBPayoutRedemptionPaymentTerminal JBEthTerminal;
    IJBProjects JBProjects;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth"); // Will start on latest block by default

        // Collect the mainnet deployment addresses
        JBController = IJBController(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBController.json"),
                "address"
            )
        );

        JBEthTerminal = IJBPayoutRedemptionPaymentTerminal(
            stdJson.readAddress(
                vm.readFile(
                    "./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBETHPaymentTerminal.json"
                ),
                "address"
            )
        );

        JBDirectory = JBController.directory();
        JBFundingCycleStore = JBController.fundingCycleStore();
        JBProjects = JBController.projects();
    }

    function testTest() public {
        emit log_address(address(JBController.directory()));
    }
}
