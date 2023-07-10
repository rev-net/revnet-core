// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Empty.sol";

contract EmptyTest_Unit is Test {
    function setUp() public {}

    function testTest() public {
        Empty empty = new Empty();
    }
}
