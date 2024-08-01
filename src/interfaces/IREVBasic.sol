// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";

import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";

interface IREVBasic {
    event ReplaceSplitOperator(uint256 indexed revnetId, address indexed newSplitOperator, address caller);
    event DeploySuckers(
        uint256 indexed revnetId,
        bytes32 indexed salt,
        bytes encodedConfiguration,
        REVSuckerDeploymentConfig suckerDeploymentConfiguration,
        address caller
    );

    event DeployRevnet(
        uint256 indexed revnetId,
        bytes32 indexed suckerSalt,
        REVConfig configuration,
        JBTerminalConfig[] terminalConfigurations,
        REVBuybackHookConfig buybackHookConfiguration,
        REVSuckerDeploymentConfig suckerDeploymentConfiguration,
        JBRulesetConfig[] rulesetConfigurations,
        bytes encodedConfiguration,
        address caller
    );

    event SetCashOutDelay(uint256 indexed revnetId, uint256 cashOutDelay, address caller);

    event Mint(
        uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
    );

    event StoreMintPotential(
        uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
    );

    event SetAdditionalOperator(uint256 revnetId, address additionalOperator, uint256[] permissionIds, address caller);

    function CASH_OUT_DELAY() external view returns (uint256);
    function CONTROLLER() external view returns (IJBController);
    function FEE() external view returns (uint256);
    function SUCKER_REGISTRY() external view returns (IJBSuckerRegistry);
    function FEE_REVNET_ID() external view returns (uint256);

    function buybackHookOf(uint256 revnetId) external view returns (IJBRulesetDataHook);
    function cashOutDelayOf(uint256 revnetId) external view returns (uint256);
    function totalPendingAutomintAmountOf(uint256 revnetId) external view returns (uint256);
    function loansOf(uint256 revnetId) external view returns (address);
    function payHookSpecificationsOf(uint256 revnetId) external view returns (JBPayHookSpecification[] memory);
    function isSplitOperatorOf(uint256 revnetId, address addr) external view returns (bool);

    function replaceSplitOperatorOf(uint256 revnetId, address newSplitOperator) external;
    function mintFor(uint256 revnetId, uint256 stageId, address beneficiary) external;
    function amountToAutoMint(
        uint256 revnetId,
        uint256 stageId,
        address beneficiary
    )
        external
        view
        returns (uint256);

    // function deploySuckersFor(
    //     uint256 projectId,
    //     bytes memory encodedConfiguration,
    //     REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    // )
    //     external;
}
