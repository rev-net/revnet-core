// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {CTPublisher} from "@croptop/core/src/CTPublisher.sol";

import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";
import {REVCroptopAllowedPost} from "../structs/REVCroptopAllowedPost.sol";
import {REVDeploy721TiersHookConfig} from "../structs/REVDeploy721TiersHookConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";

interface IREVDeployer {
    event ReplaceSplitOperator(uint256 indexed revnetId, address indexed newSplitOperator, address caller);
    event DeploySuckers(
        uint256 indexed revnetId,
        bytes32 indexed salt,
        bytes32 encodedConfigurationHash,
        REVSuckerDeploymentConfig suckerDeploymentConfiguration,
        address caller
    );

    event DeployRevnet(
        uint256 indexed revnetId,
        REVConfig configuration,
        JBTerminalConfig[] terminalConfigurations,
        REVBuybackHookConfig buybackHookConfiguration,
        REVSuckerDeploymentConfig suckerDeploymentConfiguration,
        JBRulesetConfig[] rulesetConfigurations,
        bytes32 encodedConfigurationHash,
        address caller
    );

    event SetCashOutDelay(uint256 indexed revnetId, uint256 cashOutDelay, address caller);

    event AutoIssue(
        uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
    );

    event StoreAutoIssuanceAmount(
        uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
    );

    event SetAdditionalOperator(uint256 revnetId, address additionalOperator, uint256[] permissionIds, address caller);

    function CASH_OUT_DELAY() external view returns (uint256);
    function CONTROLLER() external view returns (IJBController);
    function DIRECTORY() external view returns (IJBDirectory);
    function PROJECTS() external view returns (IJBProjects);
    function PERMISSIONS() external view returns (IJBPermissions);
    function FEE() external view returns (uint256);
    function SUCKER_REGISTRY() external view returns (IJBSuckerRegistry);
    function FEE_REVNET_ID() external view returns (uint256);
    function PUBLISHER() external view returns (CTPublisher);
    function HOOK_DEPLOYER() external view returns (IJB721TiersHookDeployer);

    function amountToAutoIssue(
        uint256 revnetId,
        uint256 stageId,
        address beneficiary
    )
        external
        view
        returns (uint256);
    function buybackHookOf(uint256 revnetId) external view returns (IJBRulesetDataHook);
    function cashOutDelayOf(uint256 revnetId) external view returns (uint256);
    function deploySuckersFor(
        uint256 revnetId,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (address[] memory suckers);
    function hashedEncodedConfigurationOf(uint256 revnetId) external view returns (bytes32);
    function isSplitOperatorOf(uint256 revnetId, address addr) external view returns (bool);
    function loansOf(uint256 revnetId) external view returns (address);
    function tiered721HookOf(uint256 revnetId) external view returns (IJB721TiersHook);
    function unrealizedAutoIssuanceAmountOf(uint256 revnetId) external view returns (uint256);

    function autoIssueFor(uint256 revnetId, uint256 stageId, address beneficiary) external;
    function deployFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external
        returns (uint256);

    function deployWith721sFor(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig memory tiered721HookConfiguration,
        REVCroptopAllowedPost[] memory allowedPosts
    )
        external
        returns (uint256, IJB721TiersHook hook);

    function setSplitOperatorOf(uint256 revnetId, address newSplitOperator) external;
}
