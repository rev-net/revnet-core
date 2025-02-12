# REVDeployer
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/REVDeployer.sol)

**Inherits:**
ERC2771Context, [IREVDeployer](/src/interfaces/IREVDeployer.sol/interface.IREVDeployer.md), IJBRulesetDataHook, IJBCashOutHook, IERC721Receiver

`REVDeployer` deploys, manages, and operates Revnets.

*Revnets are unowned Juicebox projects which operate autonomously after deployment.*


## State Variables
### CASH_OUT_DELAY
The number of seconds until a revnet's participants can cash out, starting from the time when that
revnet is deployed to a new network.
- Only applies to existing revnets which are deploying onto a new network.
- To prevent liquidity/arbitrage issues which might arise when an existing revnet adds a brand-new treasury.

*30 days, in seconds.*


```solidity
uint256 public constant override CASH_OUT_DELAY = 2_592_000;
```


### FEE
The cash out fee (as a fraction out of `JBConstants.MAX_FEE`).
Cashout fees are paid to the revnet with the `FEE_REVNET_ID`.

*Fees are charged on cashouts if the cash out tax rate is greater than 0%.*

*When suckers withdraw funds, they do not pay cash out fees.*


```solidity
uint256 public constant override FEE = 25;
```


### CONTROLLER
The controller used to create and manage Juicebox projects for revnets.


```solidity
IJBController public immutable override CONTROLLER;
```


### DIRECTORY
The directory of terminals and controllers for Juicebox projects (and revnets).


```solidity
IJBDirectory public immutable override DIRECTORY;
```


### FEE_REVNET_ID
The Juicebox project ID of the revnet that receives cash out fees.


```solidity
uint256 public immutable override FEE_REVNET_ID;
```


### HOOK_DEPLOYER
Deploys tiered ERC-721 hooks for revnets.


```solidity
IJB721TiersHookDeployer public immutable override HOOK_DEPLOYER;
```


### PERMISSIONS
Stores Juicebox project (and revnet) access permissions.


```solidity
IJBPermissions public immutable override PERMISSIONS;
```


### PROJECTS
Mints ERC-721s that represent Juicebox project (and revnet) ownership and transfers.


```solidity
IJBProjects public immutable override PROJECTS;
```


### PUBLISHER
Manages the publishing of ERC-721 posts to revnet's tiered ERC-721 hooks.


```solidity
CTPublisher public immutable override PUBLISHER;
```


### SUCKER_REGISTRY
Deploys and tracks suckers for revnets.


```solidity
IJBSuckerRegistry public immutable override SUCKER_REGISTRY;
```


### amountToAutoIssue
The number of revnet tokens which can be "auto-minted" (minted without payments)
for a specific beneficiary during a stage. Think of this as a per-stage premint.

*These tokens can be minted with `autoIssueFor(…)`.*


```solidity
mapping(uint256 revnetId => mapping(uint256 stageId => mapping(address beneficiary => uint256))) public override
    amountToAutoIssue;
```


### buybackHookOf
Each revnet's buyback data hook. These return buyback hook data.

*Buyback hooks are a combined data hook/pay hook.*


```solidity
mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public override buybackHookOf;
```


### cashOutDelayOf
The timestamp of when cashouts will become available to a specific revnet's participants.

*Only applies to existing revnets which are deploying onto a new network.*


```solidity
mapping(uint256 revnetId => uint256 cashOutDelay) public override cashOutDelayOf;
```


### hashedEncodedConfigurationOf
The hashed encoded configuration of each revnet.

*This is used to ensure that the encoded configuration of a revnet is the same when deploying suckers for
omnichain operations.*


```solidity
mapping(uint256 revnetId => bytes32 hashedEncodedConfiguration) public override hashedEncodedConfigurationOf;
```


### loansOf
Each revnet's loan contract.

*Revnets can offer loans to their participants, collateralized by their tokens.
Participants can borrow up to the current cash out value of their tokens.*


```solidity
mapping(uint256 revnetId => address) public override loansOf;
```


### tiered721HookOf
Each revnet's tiered ERC-721 hook.


```solidity
mapping(uint256 revnetId => IJB721TiersHook tiered721Hook) public override tiered721HookOf;
```


### _extraOperatorPermissions
A list of `JBPermissonIds` indices to grant to the split operator of a specific revnet.

*These should be set in the revnet's deployment process.*


```solidity
mapping(uint256 revnetId => uint256[]) internal _extraOperatorPermissions;
```


## Functions
### constructor


```solidity
constructor(
    IJBController controller,
    IJBSuckerRegistry suckerRegistry,
    uint256 feeRevnetId,
    IJB721TiersHookDeployer hookDeployer,
    CTPublisher publisher,
    address trustedForwarder
)
    ERC2771Context(trustedForwarder);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`IJBController`|The controller to use for launching and operating the Juicebox projects which will be revnets.|
|`suckerRegistry`|`IJBSuckerRegistry`|The registry to use for deploying and tracking each revnet's suckers.|
|`feeRevnetId`|`uint256`|The Juicebox project ID of the revnet that will receive fees.|
|`hookDeployer`|`IJB721TiersHookDeployer`|The deployer to use for revnet's tiered ERC-721 hooks.|
|`publisher`|`CTPublisher`|The croptop publisher revnets can use to publish ERC-721 posts to their tiered ERC-721 hooks.|
|`trustedForwarder`|`address`|The trusted forwarder for the ERC2771Context.|


### beforePayRecordedWith

Before a revnet processes an incoming payment, determine the weight and pay hooks to use.

*This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a payment.*


```solidity
function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
    external
    view
    override
    returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforePayRecordedContext`|Standard Juicebox payment context. See `JBBeforePayRecordedContext`.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The weight which revnet tokens are minted relative to. This can be used to customize how many tokens get minted by a payment.|
|`hookSpecifications`|`JBPayHookSpecification[]`|Amounts (out of what's being paid in) to be sent to pay hooks instead of being paid into the revnet. Useful for automatically routing funds from a treasury as payments come in.|


### beforeCashOutRecordedWith

Determine how a cash out from a revnet should be processed.

*This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a cash out.*

*If a sucker is cashing out, no taxes or fees are imposed.*


```solidity
function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
    external
    view
    override
    returns (
        uint256 cashOutTaxRate,
        uint256 cashOutCount,
        uint256 totalSupply,
        JBCashOutHookSpecification[] memory hookSpecifications
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforeCashOutRecordedContext`|Standard Juicebox cash out context. See `JBBeforeCashOutRecordedContext`.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`cashOutTaxRate`|`uint256`|The cash out tax rate, which influences the amount of terminal tokens which get cashed out.|
|`cashOutCount`|`uint256`|The number of revnet tokens that are cashed out.|
|`totalSupply`|`uint256`|The total revnet token supply.|
|`hookSpecifications`|`JBCashOutHookSpecification[]`|The amount of funds and the data to send to cash out hooks (this contract).|


### hasMintPermissionFor

A flag indicating whether an address has permission to mint a revnet's tokens on-demand.

*Required by the `IJBRulesetDataHook` interface.*


```solidity
function hasMintPermissionFor(uint256 revnetId, address addr) external view override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to check permissions for.|
|`addr`|`address`|The address to check the mint permission of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|flag A flag indicating whether the address has permission to mint the revnet's tokens on-demand.|


### onERC721Received

*Make sure this contract can only receive project NFTs from `JBProjects`.*


```solidity
function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4);
```

### isSplitOperatorOf

A flag indicating whether an address is a revnet's split operator.


```solidity
function isSplitOperatorOf(uint256 revnetId, address addr) public view override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet.|
|`addr`|`address`|The address to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|flag A flag indicating whether the address is the revnet's split operator.|


### supportsInterface

Indicates if this contract adheres to the specified interface.

*See `IERC165.supportsInterface`.*


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|A flag indicating if the provided interface ID is supported.|


### _checkIfIsSplitOperatorOf

If the specified address is not the revnet's current split operator, revert.


```solidity
function _checkIfIsSplitOperatorOf(uint256 revnetId, address operator) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to check split operator status for.|
|`operator`|`address`|The address being checked.|


### _isSuckerOf

A flag indicating whether an address is a revnet's sucker.


```solidity
function _isSuckerOf(uint256 revnetId, address addr) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to check sucker status for.|
|`addr`|`address`|The address being checked.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|isSucker A flag indicating whether the address is one of the revnet's suckers.|


### _makeLoanFundAccessLimits

Initialize a fund access limit group for the loan contract to use.

*Returns an unlimited surplus allowance for each token which can be loaned out.*


```solidity
function _makeLoanFundAccessLimits(
    REVConfig calldata configuration,
    JBTerminalConfig[] calldata terminalConfigurations
)
    internal
    pure
    returns (JBFundAccessLimitGroup[] memory fundAccessLimitGroups);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`configuration`|`REVConfig`|The revnet's configuration.|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to set up for the revnet. Used for payments and cash outs.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fundAccessLimitGroups`|`JBFundAccessLimitGroup[]`|The fund access limit groups for the loans.|


### _makeRulesetConfiguration

Make a ruleset configuration for a revnet's stage.


```solidity
function _makeRulesetConfiguration(
    uint32 baseCurrency,
    REVStageConfig calldata stageConfiguration,
    JBFundAccessLimitGroup[] memory fundAccessLimitGroups
)
    internal
    view
    returns (JBRulesetConfig memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`baseCurrency`|`uint32`|The base currency of the revnet.|
|`stageConfiguration`|`REVStageConfig`|The stage configuration to make a ruleset for.|
|`fundAccessLimitGroups`|`JBFundAccessLimitGroup[]`|The fund access limit groups to set up for the ruleset.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`JBRulesetConfig`|rulesetConfiguration The ruleset configuration.|


### _matchingCurrencyOf

Returns the currency of the loan source, if a matching terminal configuration is found.


```solidity
function _matchingCurrencyOf(
    JBTerminalConfig[] calldata terminalConfigurations,
    REVLoanSource calldata loanSource
)
    internal
    pure
    returns (uint32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to check.|
|`loanSource`|`REVLoanSource`|The loan source to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint32`|currency The currency of the loan source.|


### _splitOperatorPermissionIndexesOf

Returns the permissions that the split operator should be granted for a revnet.


```solidity
function _splitOperatorPermissionIndexesOf(uint256 revnetId)
    internal
    view
    returns (uint256[] memory allOperatorPermissions);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to get split operator permissions for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allOperatorPermissions`|`uint256[]`|The permissions that the split operator should be granted for the revnet, including both default and custom permissions.|


### afterCashOutRecordedWith

Processes the fee from a cash out.


```solidity
function afterCashOutRecordedWith(JBAfterCashOutRecordedContext calldata context) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterCashOutRecordedContext`|Cash out context passed in by the terminal.|


### autoIssueFor

Auto-mint a revnet's tokens from a stage for a beneficiary.


```solidity
function autoIssueFor(uint256 revnetId, uint256 stageId, address beneficiary) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to auto-mint tokens from.|
|`stageId`|`uint256`|The ID of the stage auto-mint tokens are available from.|
|`beneficiary`|`address`|The address to auto-mint tokens to.|


### deployFor

Launch a revnet, or convert an existing Juicebox project into a revnet.


```solidity
function deployFor(
    uint256 revnetId,
    REVConfig calldata configuration,
    JBTerminalConfig[] calldata terminalConfigurations,
    REVBuybackHookConfig calldata buybackHookConfiguration,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
)
    external
    override
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.|
|`configuration`|`REVConfig`|Core revnet configuration. See `REVConfig`.|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to set up for the revnet. Used for payments and cash outs.|
|`buybackHookConfiguration`|`REVBuybackHookConfig`|The buyback hook and pools to set up for the revnet. The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.|
|`suckerDeploymentConfiguration`|`REVSuckerDeploymentConfig`|The suckers to set up for the revnet. Suckers facilitate cross-chain token transfers between peer revnets on different networks.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|revnetId The ID of the newly created revnet.|


### deploySuckersFor

Deploy new suckers for an existing revnet.

*Only the revnet's split operator can deploy new suckers.*


```solidity
function deploySuckersFor(
    uint256 revnetId,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
)
    external
    override
    returns (address[] memory suckers);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to deploy suckers for. See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration from the `DeployRevnet` event emitted by this contract.|
|`suckerDeploymentConfiguration`|`REVSuckerDeploymentConfig`|The suckers to set up for the revnet.|


### deployWith721sFor

Launch a revnet which sells tiered ERC-721s and (optionally) allows croptop posts to its ERC-721 tiers.


```solidity
function deployWith721sFor(
    uint256 revnetId,
    REVConfig calldata configuration,
    JBTerminalConfig[] calldata terminalConfigurations,
    REVBuybackHookConfig calldata buybackHookConfiguration,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
    REVDeploy721TiersHookConfig calldata tiered721HookConfiguration,
    REVCroptopAllowedPost[] calldata allowedPosts
)
    external
    override
    returns (uint256, IJB721TiersHook hook);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.|
|`configuration`|`REVConfig`|Core revnet configuration. See `REVConfig`.|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to set up for the revnet. Used for payments and cash outs.|
|`buybackHookConfiguration`|`REVBuybackHookConfig`|The buyback hook and pools to set up for the revnet. The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.|
|`suckerDeploymentConfiguration`|`REVSuckerDeploymentConfig`|The suckers to set up for the revnet. Suckers facilitate cross-chain token transfers between peer revnets on different networks.|
|`tiered721HookConfiguration`|`REVDeploy721TiersHookConfig`|How to set up the tiered ERC-721 hook for the revnet.|
|`allowedPosts`|`REVCroptopAllowedPost[]`|Restrictions on which croptop posts are allowed on the revnet's ERC-721 tiers.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|revnetId The ID of the newly created revnet.|
|`hook`|`IJB721TiersHook`|The address of the tiered ERC-721 hook that was deployed for the revnet.|


### setSplitOperatorOf

Change a revnet's split operator.

*Only a revnet's current split operator can set a new split operator.*


```solidity
function setSplitOperatorOf(uint256 revnetId, address newSplitOperator) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to set the split operator of.|
|`newSplitOperator`|`address`|The new split operator's address.|


### _beforeTransferTo

Logic to be triggered before transferring tokens from this contract.


```solidity
function _beforeTransferTo(address to, address token, uint256 amount) internal returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|The address the transfer is going to.|
|`token`|`address`|The token being transferred.|
|`amount`|`uint256`|The number of tokens being transferred, as a fixed point number with the same number of decimals as the token specifies.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|payValue The value to attach to the transaction being sent.|


### _configurePostingCriteriaFor

Configure croptop posting.


```solidity
function _configurePostingCriteriaFor(
    address hook,
    REVCroptopAllowedPost[] calldata allowedPosts
)
    internal
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The hook that will be posted to.|
|`allowedPosts`|`REVCroptopAllowedPost[]`|The type of posts that the revent should allow.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|flag A flag indicating if posts were configured. Returns false if there were no posts to set up.|


### _deploy721RevnetFor

Deploy a revnet which sells tiered ERC-721s and (optionally) allows croptop posts to its ERC-721 tiers.


```solidity
function _deploy721RevnetFor(
    uint256 revnetId,
    bool shouldDeployNewRevnet,
    REVConfig calldata configuration,
    JBTerminalConfig[] calldata terminalConfigurations,
    REVBuybackHookConfig calldata buybackHookConfiguration,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
    REVDeploy721TiersHookConfig calldata tiered721HookConfiguration,
    REVCroptopAllowedPost[] calldata allowedPosts
)
    internal
    returns (IJB721TiersHook hook);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.|
|`shouldDeployNewRevnet`|`bool`|Whether to deploy a new revnet or convert an existing Juicebox project into a revnet.|
|`configuration`|`REVConfig`|Core revnet configuration. See `REVConfig`.|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to set up for the revnet. Used for payments and cash outs.|
|`buybackHookConfiguration`|`REVBuybackHookConfig`|The buyback hook and pools to set up for the revnet. The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.|
|`suckerDeploymentConfiguration`|`REVSuckerDeploymentConfig`|The suckers to set up for the revnet. Suckers facilitate cross-chain token transfers between peer revnets on different networks.|
|`tiered721HookConfiguration`|`REVDeploy721TiersHookConfig`|How to set up the tiered ERC-721 hook for the revnet.|
|`allowedPosts`|`REVCroptopAllowedPost[]`|Restrictions on which croptop posts are allowed on the revnet's ERC-721 tiers.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`IJB721TiersHook`|The address of the tiered ERC-721 hook that was deployed for the revnet.|


### _deployRevnetFor

Deploy a revnet, or convert an existing Juicebox project into a revnet.


```solidity
function _deployRevnetFor(
    uint256 revnetId,
    bool shouldDeployNewRevnet,
    REVConfig calldata configuration,
    JBTerminalConfig[] calldata terminalConfigurations,
    REVBuybackHookConfig calldata buybackHookConfiguration,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
    JBRulesetConfig[] memory rulesetConfigurations,
    bytes32 encodedConfigurationHash
)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.|
|`shouldDeployNewRevnet`|`bool`|Whether to deploy a new revnet or convert an existing Juicebox project into a revnet.|
|`configuration`|`REVConfig`|Core revnet configuration. See `REVConfig`.|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to set up for the revnet. Used for payments and cash outs.|
|`buybackHookConfiguration`|`REVBuybackHookConfig`|The buyback hook and pools to set up for the revnet. The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.|
|`suckerDeploymentConfiguration`|`REVSuckerDeploymentConfig`|The suckers to set up for the revnet. Suckers facilitate cross-chain token transfers between peer revnets on different networks.|
|`rulesetConfigurations`|`JBRulesetConfig[]`|The rulesets to set up for the revnet.|
|`encodedConfigurationHash`|`bytes32`|A hash that represents the revnet's configuration. See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration from the `DeployRevnet` event emitted by this contract.|


### _deploySuckersFor

Deploy suckers for a revnet.


```solidity
function _deploySuckersFor(
    uint256 revnetId,
    bytes32 encodedConfigurationHash,
    REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
)
    internal
    returns (address[] memory suckers);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to deploy suckers for.|
|`encodedConfigurationHash`|`bytes32`|A hash that represents the revnet's configuration. See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration from the `DeployRevnet` event emitted by this contract.|
|`suckerDeploymentConfiguration`|`REVSuckerDeploymentConfig`|The suckers to set up for the revnet.|


### _makeRulesetConfigurations

Convert a revnet's stages into a series of Juicebox project rulesets.


```solidity
function _makeRulesetConfigurations(
    uint256 revnetId,
    REVConfig calldata configuration,
    JBTerminalConfig[] calldata terminalConfigurations
)
    internal
    returns (JBRulesetConfig[] memory rulesetConfigurations, bytes32 encodedConfigurationHash);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to make rulesets for.|
|`configuration`|`REVConfig`|The configuration containing the revnet's stages.|
|`terminalConfigurations`|`JBTerminalConfig[]`|The terminals to set up for the revnet. Used for payments and cash outs.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`rulesetConfigurations`|`JBRulesetConfig[]`|A list of ruleset configurations defined by the stages.|
|`encodedConfigurationHash`|`bytes32`|A hash that represents the revnet's configuration. Used for sucker deployment salts.|


### _mintTokensOf

Mints a revnet's tokens.


```solidity
function _mintTokensOf(uint256 revnetId, uint256 tokenCount, address beneficiary) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to mint tokens for.|
|`tokenCount`|`uint256`|The number of tokens to mint.|
|`beneficiary`|`address`|The address to send the tokens to.|


### _setCashOutDelayIfNeeded

Sets the cash out delay if the revnet's stages are already in progress.

*This prevents cash out liquidity/arbitrage issues for existing revnets which
are deploying to a new chain.*


```solidity
function _setCashOutDelayIfNeeded(uint256 revnetId, REVStageConfig calldata firstStageConfig) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to set the cash out delay for.|
|`firstStageConfig`|`REVStageConfig`|The revnet's first stage.|


### _setPermission

Grants a permission to an address (an "operator").


```solidity
function _setPermission(address operator, uint256 revnetId, uint8 permissionId) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The address to give the permission to.|
|`revnetId`|`uint256`|The ID of the revnet to scope the permission for.|
|`permissionId`|`uint8`|The ID of the permission to set. See `JBPermissionIds`.|


### _setPermissionsFor

Grants a permission to an address (an "operator").


```solidity
function _setPermissionsFor(
    address account,
    address operator,
    uint256 revnetId,
    uint8[] memory permissionIds
)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The account granting the permission.|
|`operator`|`address`|The address to give the permission to.|
|`revnetId`|`uint256`|The ID of the revnet to scope the permission for.|
|`permissionIds`|`uint8[]`|An array of permission IDs to set. See `JBPermissionIds`.|


### _setSplitOperatorOf

Give a split operator their permissions.

*Only a revnet's current split operator can set a new split operator, by calling `setSplitOperatorOf(…)`.*


```solidity
function _setSplitOperatorOf(uint256 revnetId, address operator) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to set the split operator of.|
|`operator`|`address`|The new split operator's address.|


## Errors
### REVDeployer_LoanSourceDoesntMatchTerminalConfigurations

```solidity
error REVDeployer_LoanSourceDoesntMatchTerminalConfigurations(address token, address terminal);
```

### REVDeployer_AutoIssuanceBeneficiaryZeroAddress

```solidity
error REVDeployer_AutoIssuanceBeneficiaryZeroAddress();
```

### REVDeployer_CashOutDelayNotFinished

```solidity
error REVDeployer_CashOutDelayNotFinished(uint256 cashOutDelay, uint256 blockTimestamp);
```

### REVDeployer_CashOutsCantBeTurnedOffCompletely

```solidity
error REVDeployer_CashOutsCantBeTurnedOffCompletely(uint256 cashOutTaxRate, uint256 maxCashOutTaxRate);
```

### REVDeployer_MustHaveSplits

```solidity
error REVDeployer_MustHaveSplits();
```

### REVDeployer_RulesetDoesNotAllowDeployingSuckers

```solidity
error REVDeployer_RulesetDoesNotAllowDeployingSuckers();
```

### REVDeployer_StageNotStarted

```solidity
error REVDeployer_StageNotStarted(uint256 stageStartTime, uint256 blockTimestamp);
```

### REVDeployer_StagesRequired

```solidity
error REVDeployer_StagesRequired();
```

### REVDeployer_StageTimesMustIncrease

```solidity
error REVDeployer_StageTimesMustIncrease();
```

### REVDeployer_Unauthorized

```solidity
error REVDeployer_Unauthorized(uint256 revnetId, address caller);
```

