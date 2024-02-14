// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

// import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
// import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
// import {REVBuybackHookConfig} from "../src/structs/REVBuybackHookConfig.sol";
// import {REVConfig} from "../src/structs/REVConfig.sol";
// import {REVBoostConfig} from "../src/structs/REVBoostConfig.sol";

contract REVBasicDeployerTest is Test {
// // IJBProjects PROJECTS;
// // IJBPermissions PERMISSIONS;

// function setUp() public {
//     // // Deploy the permissions contract.
//     // PERMISSIONS = new JBPermissions();
//     // // Deploy the projects contract.
//     // PROJECTS = new JBProjects(address(123));

// }

// function testdeployerbecomesowner(
//     address projectOwner,
//     address owner
// )
//     public
// {
//     string memory name = "token name";
//     string memory symbol = "token symbol";
//     string memory metadata = "im a revnet";
//     REVBoostConfig[] memory boosts = new REVBoostConfig[](1);
//     boosts[0] = REVBoostConfig({
//         rate: 1,
//         startsAtOrAfter: 0
//     });
//     REVConfig memory deployConfig = REVConfig({
//         baseCurrency: JBConstants.NATIVE_TOKEN,
//         initialIssuanceRate: 1000,
//         premintTokenAmount: 1000
//         priceCeilingIncreaseFrequency: 100,
//         priceCeilingIncreasePercentage: 100,
//         priceFloorTaxIntensity: 100,
//         boosts: boosts
//     });
//     address boostOperator = address(123);
//     JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
//     address[] memory tokensToAccept = new address[](0);
//     tokensToAccept[0] = JBConstants.NATIVE_TOKEN;
//     terminalConfigurations = JBTerminalConfig({
//             terminal: address(13);
//             tokensToAccept: tokensToAccept
//     });

//     REVBuybackPoolConfig[] memory poolConfigurations = new REVBuybackPoolConfig[](1);

//     REVBuybackHookConfig memory buybackHookConfiguration = REVBuybackHookConfig({
//         hook: address(0),
//         poolConfigurations: poolConfigurations
//     });

//     revnetId = deployRevnetFor({
//         name: tokenName,
//         symbol: symbol,
//         metadata: revnetMetadata,
//         deployConfig: deployConfig,
//         boostOperator: boostOperator,
//         terminalConfigurations: terminalConfigurations,
//         buybackHookConfiguration: buybackHookConfiguration
//     });

//     // `CreateFor` won't work if the address is a contract that doesn't support `ERC721Receiver`.
//     // vm.assume(projectOwner != address(0));

//     assertEq(uint256(1), uint256(1));
// }
}
