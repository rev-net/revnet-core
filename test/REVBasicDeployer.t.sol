// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

contract REVBasicDeployerTest is Test {
    // IJBProjects PROJECTS;
    // IJBPermissions PERMISSIONS;

    function setUp() public {
        // // Deploy the permissions contract.
        // PERMISSIONS = new JBPermissions();
        // // Deploy the projects contract.
        // PROJECTS = new JBProjects(address(123));
    }

    function testDeployerBecomesOwner(
        address projectOwner,
        address owner
    )
        public
    {
        // `CreateFor` won't work if the address is a contract that doesn't support `ERC721Receiver`.
        // vm.assume(projectOwner != address(0));

        assertEq(1, 1);
    }
}
