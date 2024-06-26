pragma solidity ^0.8.0;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {IBPSuckerRegistry} from "@bananapus/suckers/src/interfaces/IBPSuckerRegistry.sol";
import {IJBProjectHandles} from "@bananapus/project-handles/src/interfaces/IJBProjectHandles.sol";

import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVSuckerDeploymentConfig} from "../structs/REVSuckerDeploymentConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";

interface IREVBasicDeployer {
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
        REVConfig configuration,
        JBTerminalConfig[] terminalConfigurations,
        REVBuybackHookConfig buybackHookConfiguration,
        REVSuckerDeploymentConfig suckerDeploymentConfiguration,
        JBRulesetConfig[] rulesetConfigurations,
        bytes encodedConfiguration,
        bool isInProgress,
        address caller
    );

    event Mint(
        uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
    );

    event StoreMintPotential(
        uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
    );

    function EXIT_DELAY() external view returns (uint256);
    function CONTROLLER() external view returns (IJBController);
    function SUCKER_REGISTRY() external view returns (IBPSuckerRegistry);
    function PROJECT_HANDLES() external view returns (IJBProjectHandles);

    function buybackHookOf(uint256 revnetId) external view returns (IJBRulesetDataHook);
    function exitDelayOf(uint256 revnetId) external view returns (uint256);
    function payHookSpecificationsOf(uint256 revnetId) external view returns (JBPayHookSpecification[] memory);
    function isSplitOperatorOf(uint256 revnetId, address addr) external view returns (bool);

    function replaceSplitOperatorOf(uint256 revnetId, address newSplitOperator) external;
    function mintFor(uint256 revnetId, uint256 stageId, address beneficiary) external;
    function setEnsNamePartsFor(uint256 chainId, uint256 revnetId, string[] memory parts) external;

    function launchRevnetFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external
        returns (uint256);

    function deploySuckersFor(
        uint256 projectId,
        bytes memory encodedConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external;
}
