# IREVDeployer
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/interfaces/IREVDeployer.sol)


## Functions
### CASH_OUT_DELAY


```solidity
function CASH_OUT_DELAY() external view returns (uint256);
```

### CONTROLLER


```solidity
function CONTROLLER() external view returns (IJBController);
```

### DIRECTORY


```solidity
function DIRECTORY() external view returns (IJBDirectory);
```

### PROJECTS


```solidity
function PROJECTS() external view returns (IJBProjects);
```

### PERMISSIONS


```solidity
function PERMISSIONS() external view returns (IJBPermissions);
```

### FEE


```solidity
function FEE() external view returns (uint256);
```

### SUCKER_REGISTRY


```solidity
function SUCKER_REGISTRY() external view returns (IJBSuckerRegistry);
```

### FEE_REVNET_ID


```solidity
function FEE_REVNET_ID() external view returns (uint256);
```

### PUBLISHER


```solidity
function PUBLISHER() external view returns (CTPublisher);
```

### HOOK_DEPLOYER


```solidity
function HOOK_DEPLOYER() external view returns (IJB721TiersHookDeployer);
```

### amountToAutoIssue


```solidity
function amountToAutoIssue(uint256 revnetId, uint256 stageId, address beneficiary) external view returns (uint256);
```

### buybackHookOf


```solidity
function buybackHookOf(uint256 revnetId) external view returns (IJBRulesetDataHook);
```

### cashOutDelayOf


```solidity
function cashOutDelayOf(uint256 revnetId) external view returns (uint256);
```

### deploySuckersFor


```solidity
function deploySuckersFor(
    uint256 revnetId,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
)
    external
    returns (address[] memory suckers);
```

### hashedEncodedConfigurationOf


```solidity
function hashedEncodedConfigurationOf(uint256 revnetId) external view returns (bytes32);
```

### isSplitOperatorOf


```solidity
function isSplitOperatorOf(uint256 revnetId, address addr) external view returns (bool);
```

### loansOf


```solidity
function loansOf(uint256 revnetId) external view returns (address);
```

### tiered721HookOf


```solidity
function tiered721HookOf(uint256 revnetId) external view returns (IJB721TiersHook);
```

### autoIssueFor


```solidity
function autoIssueFor(uint256 revnetId, uint256 stageId, address beneficiary) external;
```

### deployFor


```solidity
function deployFor(
    uint256 revnetId,
    REVConfig memory configuration,
    JBTerminalConfig[] memory terminalConfigurations,
    REVBuybackHookConfig memory buybackHookConfiguration,
    REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
)
    external
    returns (uint256);
```

### deployWith721sFor


```solidity
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
```

### setSplitOperatorOf


```solidity
function setSplitOperatorOf(uint256 revnetId, address newSplitOperator) external;
```

## Events
### ReplaceSplitOperator

```solidity
event ReplaceSplitOperator(uint256 indexed revnetId, address indexed newSplitOperator, address caller);
```

### DeploySuckers

```solidity
event DeploySuckers(
    uint256 indexed revnetId,
    bytes32 indexed salt,
    bytes32 encodedConfigurationHash,
    REVSuckerDeploymentConfig suckerDeploymentConfiguration,
    address caller
);
```

### DeployRevnet

```solidity
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
```

### SetCashOutDelay

```solidity
event SetCashOutDelay(uint256 indexed revnetId, uint256 cashOutDelay, address caller);
```

### AutoIssue

```solidity
event AutoIssue(
    uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
);
```

### StoreAutoIssuanceAmount

```solidity
event StoreAutoIssuanceAmount(
    uint256 indexed revnetId, uint256 indexed stageId, address indexed beneficiary, uint256 count, address caller
);
```

### SetAdditionalOperator

```solidity
event SetAdditionalOperator(uint256 revnetId, address additionalOperator, uint256[] permissionIds, address caller);
```

