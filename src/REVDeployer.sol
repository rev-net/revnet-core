// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {IJBCashOutHook} from "@bananapus/core/src/interfaces/IJBCashOutHook.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPayHook} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {JBCashOuts} from "@bananapus/core/src/libraries/JBCashOuts.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBAfterCashOutRecordedContext} from "@bananapus/core/src/structs/JBAfterCashOutRecordedContext.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core/src/structs/JBBeforeCashOutRecordedContext.sol";
import {JBCurrencyAmount} from "@bananapus/core/src/structs/JBCurrencyAmount.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core/src/structs/JBFundAccessLimitGroup.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core/src/structs/JBSplitGroup.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBCashOutHookSpecification} from "@bananapus/core/src/structs/JBCashOutHookSpecification.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {CTPublisher} from "@croptop/core/src/CTPublisher.sol";
import {CTAllowedPost} from "@croptop/core/src/structs/CTAllowedPost.sol";

import {IREVDeployer} from "./interfaces/IREVDeployer.sol";
import {REVAutoIssuance} from "./structs/REVAutoIssuance.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "./structs/REVBuybackPoolConfig.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVCroptopAllowedPost} from "./structs/REVCroptopAllowedPost.sol";
import {REVDeploy721TiersHookConfig} from "./structs/REVDeploy721TiersHookConfig.sol";
import {REVLoanSource} from "./structs/REVLoanSource.sol";
import {REVStageConfig} from "./structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";

/// @notice `REVDeployer` deploys, manages, and operates Revnets.
/// @dev Revnets are unowned Juicebox projects which operate autonomously after deployment.
contract REVDeployer is ERC2771Context, IREVDeployer, IJBRulesetDataHook, IJBCashOutHook, IERC721Receiver {
    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error REVDeployer_LoanSourceDoesntMatchTerminalConfigurations(address token, address terminal);
    error REVDeployer_AutoIssuanceBeneficiaryZeroAddress();
    error REVDeployer_CashOutDelayNotFinished();
    error REVDeployer_CashOutsCantBeTurnedOffCompletely();
    error REVDeployer_RulesetDoesNotAllowDeployingSuckers();
    error REVDeployer_StageNotStarted();
    error REVDeployer_StagesRequired();
    error REVDeployer_StageTimesMustIncrease();
    error REVDeployer_Unauthorized();

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The number of seconds until a revnet's participants can cash out, starting from the time when that
    /// revnet is deployed to a new network.
    /// - Only applies to existing revnets which are deploying onto a new network.
    /// - To prevent liquidity/arbitrage issues which might arise when an existing revnet adds a brand-new treasury.
    /// @dev 30 days, in seconds.
    uint256 public constant override CASH_OUT_DELAY = 2_592_000;

    /// @notice The cash out fee (as a fraction out of `JBConstants.MAX_FEE`).
    /// Cashout fees are paid to the revnet with the `FEE_REVNET_ID`.
    /// @dev Fees are charged on cashouts if the cash out tax rate is greater than 0%.
    /// @dev When suckers withdraw funds, they do not pay cash out fees.
    uint256 public constant override FEE = 25; // 2.5%

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The controller used to create and manage Juicebox projects for revnets.
    IJBController public immutable override CONTROLLER;

    /// @notice The directory of terminals and controllers for Juicebox projects (and revnets).
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The Juicebox project ID of the revnet that receives cash out fees.
    uint256 public immutable override FEE_REVNET_ID;

    /// @notice Deploys tiered ERC-721 hooks for revnets.
    IJB721TiersHookDeployer public immutable override HOOK_DEPLOYER;

    /// @notice Stores Juicebox project (and revnet) access permissions.
    IJBPermissions public immutable override PERMISSIONS;

    /// @notice Mints ERC-721s that represent Juicebox project (and revnet) ownership and transfers.
    IJBProjects public immutable override PROJECTS;

    /// @notice Manages the publishing of ERC-721 posts to revnet's tiered ERC-721 hooks.
    CTPublisher public immutable override PUBLISHER;

    /// @notice Deploys and tracks suckers for revnets.
    IJBSuckerRegistry public immutable override SUCKER_REGISTRY;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The number of revnet tokens which can be "auto-minted" (minted without payments)
    /// for a specific beneficiary during a stage. Think of this as a per-stage premint.
    /// @dev These tokens can be minted with `autoIssueFor(…)`.
    /// @custom:param revnetId The ID of the revnet to get the auto-mint amount for.
    /// @custom:param stageId The ID of the stage to get the auto-mint amount for.
    /// @custom:param beneficiary The beneficiary of the auto-mint.
    mapping(uint256 revnetId => mapping(uint256 stageId => mapping(address beneficiary => uint256))) public override
        amountToAutoIssue;

    /// @notice Each revnet's buyback data hook. These return buyback hook data.
    /// @dev Buyback hooks are a combined data hook/pay hook.
    /// @custom:param revnetId The ID of the revnet to get the buyback data hook for.
    mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public override buybackHookOf;

    /// @notice The timestamp of when cashouts will become available to a specific revnet's participants.
    /// @dev Only applies to existing revnets which are deploying onto a new network.
    /// @custom:param revnetId The ID of the revnet to get the cash out delay for.
    mapping(uint256 revnetId => uint256 cashOutDelay) public override cashOutDelayOf;

    /// @notice Each revnet's loan contract.
    /// @dev Revnets can offer loans to their participants, collateralized by their tokens.
    /// Participants can borrow up to the current cash out value of their tokens.
    /// @custom:param revnetId The ID of the revnet to get the loan contract of.
    mapping(uint256 revnetId => address) public override loansOf;

    /// @notice Each revnet's tiered ERC-721 hook.
    /// @custom:param revnetId The ID of the revnet to get the tiered ERC-721 hook for.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 revnetId => IJB721TiersHook tiered721Hook) public override tiered721HookOf;

    /// @notice The amount of auto-mint tokens which have not been minted yet, including future stages, for each revnet.
    /// @dev These tokens can be realized (minted) with `autoIssueFor(…)`.
    /// @custom:param revnetId The ID of the revnet to get the unrealized auto-issuance amount for.
    mapping(uint256 revnetId => uint256) public override unrealizedAutoIssuanceAmountOf;

    //*********************************************************************//
    // ------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice A list of `JBPermissonIds` indices to grant to the split operator of a specific revnet.
    /// @dev These should be set in the revnet's deployment process.
    /// @custom:param revnetId The ID of the revnet to get the extra operator permissions for.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 revnetId => uint256[]) internal _extraOperatorPermissions;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller to use for launching and operating the Juicebox projects which will be revnets.
    /// @param suckerRegistry The registry to use for deploying and tracking each revnet's suckers.
    /// @param feeRevnetId The Juicebox project ID of the revnet that will receive fees.
    /// @param hookDeployer The deployer to use for revnet's tiered ERC-721 hooks.
    /// @param publisher The croptop publisher revnets can use to publish ERC-721 posts to their tiered ERC-721 hooks.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBController controller,
        IJBSuckerRegistry suckerRegistry,
        uint256 feeRevnetId,
        IJB721TiersHookDeployer hookDeployer,
        CTPublisher publisher,
        address trustedForwarder
    )
        ERC2771Context(trustedForwarder)
    {
        CONTROLLER = controller;
        DIRECTORY = controller.DIRECTORY();
        PROJECTS = controller.PROJECTS();
        PERMISSIONS = IJBPermissioned(address(CONTROLLER)).PERMISSIONS();
        SUCKER_REGISTRY = suckerRegistry;
        FEE_REVNET_ID = feeRevnetId;
        HOOK_DEPLOYER = hookDeployer;
        PUBLISHER = publisher;

        // Give the sucker registry permission to map tokens for all revnets.
        _setPermission({operator: address(SUCKER_REGISTRY), revnetId: 0, permissionId: JBPermissionIds.MAP_SUCKER_TOKEN});
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Before a revnet processes an incoming payment, determine the weight and pay hooks to use.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a payment.
    /// @param context Standard Juicebox payment context. See `JBBeforePayRecordedContext`.
    /// @return weight The weight which revnet tokens are minted relative to. This can be used to customize how many
    /// tokens get minted by a payment.
    /// @return hookSpecifications Amounts (out of what's being paid in) to be sent to pay hooks instead of being paid
    /// into the revnet. Useful for automatically routing funds from a treasury as payments come in.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the specifications provided by the buyback data hook.
        JBPayHookSpecification[] memory buybackHookSpecifications;

        // Keep a reference to the revnet's buyback data hook.
        IJBRulesetDataHook buybackHook = buybackHookOf[context.projectId];

        // Read the weight and specifications from the buyback data hook.
        // If there's no buyback data hook, use the default weight.
        if (buybackHook != IJBRulesetDataHook(address(0))) {
            (weight, buybackHookSpecifications) = buybackHook.beforePayRecordedWith(context);
        } else {
            weight = context.weight;
        }

        // Is there a buyback hook specification?
        bool usesBuybackHook = buybackHookSpecifications.length == 1;

        // Keep a reference to the revnet's tiered ERC-721 hook.
        IJB721TiersHook tiered721Hook = tiered721HookOf[context.projectId];

        // Is there a tiered ERC-721 hook?
        bool usesTiered721Hook = address(tiered721Hook) != address(0);

        // Initialize the returned specification array with enough room to include the specifications we're using.
        hookSpecifications = new JBPayHookSpecification[]((usesTiered721Hook ? 1 : 0) + (usesBuybackHook ? 1 : 0));

        // If we have a tiered ERC-721 hook, add it to the array.
        if (usesTiered721Hook) {
            hookSpecifications[0] =
                JBPayHookSpecification({hook: IJBPayHook(address(tiered721Hook)), amount: 0, metadata: bytes("")});
        }

        // If we have a buyback hook specification, add it to the end of the array.
        if (usesBuybackHook) hookSpecifications[1] = buybackHookSpecifications[0];
    }

    /// @notice Determine how a cash out from a revnet should be processed.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a cash out.
    /// @dev If a sucker is cashing out, no taxes or fees are imposed.
    /// @param context Standard Juicebox cash out context. See `JBBeforeCashOutRecordedContext`.
    /// @return cashOutTaxRate The cash out tax rate, which influences the amount of terminal tokens which get cashed
    /// out.
    /// @return cashOutCount The number of revnet tokens that are cashed out.
    /// @return totalSupply The total revnet token supply.
    /// @return hookSpecifications The amount of funds and the data to send to cash out hooks (this contract).
    function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
        external
        view
        override
        returns (
            uint256 cashOutTaxRate,
            uint256 cashOutCount,
            uint256 totalSupply,
            JBCashOutHookSpecification[] memory hookSpecifications
        )
    {
        // If the cash out is from a sucker, return the full cash out amount without taxes or fees.
        if (_isSuckerOf({revnetId: context.projectId, addr: context.holder})) {
            return (0, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // Enforce the cash out delay.
        if (cashOutDelayOf[context.projectId] > block.timestamp) {
            revert REVDeployer_CashOutDelayNotFinished();
        }

        // Get the terminal that will receive the cash out fee.
        IJBTerminal feeTerminal = DIRECTORY.primaryTerminalOf(FEE_REVNET_ID, context.surplus.token);

        // If there's no cash out tax (100% cash out tax rate), or if there's no fee terminal, do not charge a fee.
        if (context.cashOutTaxRate == 0 || address(feeTerminal) == address(0)) {
            return (context.cashOutTaxRate, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // Get a reference to the number of tokens being used to pay the fee (out of the total being cashed out).
        uint256 feeCashOutCount = mulDiv(context.cashOutCount, FEE, JBConstants.MAX_FEE);

        // Assemble a cash out hook specification to invoke `afterCashOutRecordedWith(…)` with, to process the fee.
        hookSpecifications = new JBCashOutHookSpecification[](1);
        hookSpecifications[0] = JBCashOutHookSpecification({
            hook: IJBCashOutHook(address(this)),
            amount: JBCashOuts.cashOutFrom({
                surplus: context.surplus.value,
                cashOutCount: feeCashOutCount,
                totalSupply: context.totalSupply,
                cashOutTaxRate: context.cashOutTaxRate
            }),
            metadata: abi.encode(feeTerminal)
        });

        // Return the cash out rate and the number of revnet tokens to cash out, minus the tokens being used to pay the
        // fee.
        return (context.cashOutTaxRate, context.cashOutCount - feeCashOutCount, context.totalSupply, hookSpecifications);
    }

    /// @notice A flag indicating whether an address has permission to mint a revnet's tokens on-demand.
    /// @dev Required by the `IJBRulesetDataHook` interface.
    /// @param revnetId The ID of the revnet to check permissions for.
    /// @param addr The address to check the mint permission of.
    /// @return flag A flag indicating whether the address has permission to mint the revnet's tokens on-demand.
    function hasMintPermissionFor(uint256 revnetId, address addr) external view override returns (bool) {
        // The buyback hook, loans contract, and suckers are allowed to mint the revnet's tokens.
        return addr == address(buybackHookOf[revnetId]) || addr == loansOf[revnetId]
            || _isSuckerOf({revnetId: revnetId, addr: addr});
    }

    /// @dev Make sure this contract can only receive project NFTs from `JBProjects`.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        // Make sure the 721 received is from the `JBProjects` contract.
        if (msg.sender != address(PROJECTS)) revert();

        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice A flag indicating if the current ruleset allows deploying new suckers.
    /// @param revnetId The ID of the revnet to check the ruleset of.
    /// @return flag A flag indicating if the current ruleset allows deploying new suckers.
    function allowsDeployingSuckersInCurrentRulesetOf(uint256 revnetId) public view returns (bool) {
        // Check if the current ruleset allows deploying new suckers.
        // slither-disable-next-line unused-return
        (, JBRulesetMetadata memory metadata) = CONTROLLER.currentRulesetOf(revnetId);
        // Check the third bit, it indicates if the ruleset allows new suckers to be deployed.
        return ((metadata.metadata >> 2) & 1) == 1;
    }

    /// @notice A flag indicating whether an address is a revnet's split operator.
    /// @param revnetId The ID of the revnet.
    /// @param addr The address to check.
    /// @return flag A flag indicating whether the address is the revnet's split operator.
    function isSplitOperatorOf(uint256 revnetId, address addr) public view override returns (bool) {
        return PERMISSIONS.hasPermissions({
            operator: addr,
            account: address(this),
            projectId: revnetId,
            permissionIds: _splitOperatorPermissionIndexesOf(revnetId),
            includeRoot: false,
            includeWildcardProjectId: false
        });
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See `IERC165.supportsInterface`.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IREVDeployer).interfaceId || interfaceId == type(IJBRulesetDataHook).interfaceId
            || interfaceId == type(IJBCashOutHook).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice If the specified address is not the revnet's current split operator, revert.
    /// @param revnetId The ID of the revnet to check split operator status for.
    /// @param operator The address being checked.
    function _checkIfIsSplitOperatorOf(uint256 revnetId, address operator) internal view {
        if (!isSplitOperatorOf(revnetId, operator)) revert REVDeployer_Unauthorized();
    }

    /// @notice Encodes an auto-issuance.
    /// @param autoIssuance The auto-issuance to encode.
    /// @return encodedAutoIssuance The encoded auto-issuance.
    function _encodedAutoIssuance(REVAutoIssuance calldata autoIssuance) private pure returns (bytes memory) {
        return abi.encode(autoIssuance.chainId, autoIssuance.beneficiary, autoIssuance.count);
    }

    /// @notice Encodes a revnet stage. This is used for sucker deployment salts.
    /// @param stageConfiguration The stage's configuration.
    /// @param stageNumber The stage's number/ID.
    /// @return encodedConfiguration The encoded stage.
    function _encodedStageConfig(
        REVStageConfig calldata stageConfiguration,
        uint256 stageNumber
    )
        internal
        view
        returns (bytes memory encodedConfiguration)
    {
        // Encode the stage.
        encodedConfiguration = abi.encode(
            // If no start time is provided for the first stage, use the current block's timestamp.
            // In the future, revnets deployed on other networks can match this revnet's encoded stage by specifying the
            // same start time.
            (stageNumber == 0 && stageConfiguration.startsAtOrAfter == 0)
                ? block.timestamp
                : stageConfiguration.startsAtOrAfter,
            stageConfiguration.splitPercent,
            stageConfiguration.initialIssuance,
            stageConfiguration.issuanceCutFrequency,
            stageConfiguration.issuanceCutPercent,
            stageConfiguration.cashOutTaxRate
        );

        // Add each auto-mint to the byte-encoded representation.
        for (uint256 i; i < stageConfiguration.autoIssuances.length; i++) {
            encodedConfiguration =
                abi.encode(encodedConfiguration, _encodedAutoIssuance(stageConfiguration.autoIssuances[i]));
        }
    }

    /// @notice A flag indicating whether an address is a revnet's sucker.
    /// @param revnetId The ID of the revnet to check sucker status for.
    /// @param addr The address being checked.
    /// @return isSucker A flag indicating whether the address is one of the revnet's suckers.
    function _isSuckerOf(uint256 revnetId, address addr) internal view returns (bool) {
        return SUCKER_REGISTRY.isSuckerOf(revnetId, addr);
    }

    /// @notice Initialize a fund access limit group for the loan contract to use.
    /// @dev Returns an unlimited surplus allowance for each token which can be loaned out.
    /// @param configuration The revnet's configuration.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @return fundAccessLimitGroups The fund access limit groups for the loans.
    function _makeLoanFundAccessLimits(
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations
    )
        internal
        pure
        returns (JBFundAccessLimitGroup[] memory fundAccessLimitGroups)
    {
        // Initialize the fund access limit groups.
        fundAccessLimitGroups = new JBFundAccessLimitGroup[](configuration.loanSources.length);

        // Set up the fund access limits for the loans.
        for (uint256 i; i < configuration.loanSources.length; i++) {
            // Set the loan source being iterated on.
            REVLoanSource calldata loanSource = configuration.loanSources[i];

            // Keep a reference to the currency of the loan source.
            uint32 currency;

            // Loop through all terminal configurations and check if the currency is the token being accepted.
            // This both protects from misconfiguration and ensures the assumption(s) we make in
            // `_makeLoanFundAccessLimits`
            // are safe.
            for (uint256 j; j < terminalConfigurations.length; j++) {
                if (terminalConfigurations[j].terminal != loanSource.terminal) {
                    for (uint256 k; k < terminalConfigurations[j].accountingContextsToAccept.length; k++) {
                        currency = terminalConfigurations[j].accountingContextsToAccept[k].currency;
                    }
                }
            }

            // If the currency is 0 it means the loan source doesn't match the terminal configurations.
            if (currency == 0) {
                revert REVDeployer_LoanSourceDoesntMatchTerminalConfigurations(
                    loanSource.token, address(loanSource.terminal)
                );
            }

            // Set up an unlimited allowance for the loan contract to use.
            JBCurrencyAmount[] memory loanAllowances = new JBCurrencyAmount[](1);
            loanAllowances[0] = JBCurrencyAmount({currency: currency, amount: type(uint224).max});

            // Set up the fund access limits for the loans.
            fundAccessLimitGroups[i] = JBFundAccessLimitGroup({
                terminal: address(loanSource.terminal),
                token: loanSource.token,
                payoutLimits: new JBCurrencyAmount[](0),
                surplusAllowances: loanAllowances
            });
        }
    }

    /// @notice Creates a reserved token split group that goes entirely to the specified split operator.
    /// @dev The operator can add other beneficiaries to the split group later, if they wish.
    /// @param splitOperator The address to send the entire split amount to.
    /// @return splitGroups The split group, entirely assigned to the operator.
    function _makeOperatorSplitGroupWith(address splitOperator)
        internal
        pure
        returns (JBSplitGroup[] memory splitGroups)
    {
        // Create a split group that assigns all of the splits to the operator.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(splitOperator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Package the reserved token splits.
        splitGroups = new JBSplitGroup[](1);
        splitGroups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: splits});
    }

    /// @notice Convert a revnet's stages into a series of Juicebox project rulesets.
    /// @param configuration The configuration containing the revnet's stages.
    /// @return rulesetConfigurations A list of ruleset configurations defined by the stages.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @return encodedConfiguration A byte-encoded representation of the revnet's configuration. Used for sucker
    /// deployment salts.
    function _makeRulesetConfigurations(
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations
    )
        internal
        view
        returns (JBRulesetConfig[] memory rulesetConfigurations, bytes memory encodedConfiguration)
    {
        // If there are no stages, revert.
        if (configuration.stageConfigurations.length == 0) revert REVDeployer_StagesRequired();

        // Initialize the array of rulesets.
        rulesetConfigurations = new JBRulesetConfig[](configuration.stageConfigurations.length);

        // Add the base configuration to the byte-encoded configuration.
        encodedConfiguration = abi.encode(
            configuration.baseCurrency,
            configuration.loans,
            configuration.description.name,
            configuration.description.ticker,
            configuration.description.salt
        );

        // Initialize fund access limit groups for the loan contract to use.
        JBFundAccessLimitGroup[] memory fundAccessLimitGroups =
            _makeLoanFundAccessLimits({configuration: configuration, terminalConfigurations: terminalConfigurations});

        // Keep a reference to the previous ruleset's start time.
        uint256 previousStartTime;

        // Iterate through each stage to set up its ruleset.
        for (uint256 i; i < configuration.stageConfigurations.length; i++) {
            // Set the stage being iterated on.
            REVStageConfig calldata stageConfiguration = configuration.stageConfigurations[i];

            // If the stage's start time is not after the previous stage's start time, revert.
            if (stageConfiguration.startsAtOrAfter <= previousStartTime) {
                revert REVDeployer_StageTimesMustIncrease();
            }

            // Make sure the revnet doesn't prevent cashouts all together.
            if (stageConfiguration.cashOutTaxRate >= JBConstants.MAX_CASH_OUT_TAX_RATE) {
                revert REVDeployer_CashOutsCantBeTurnedOffCompletely();
            }

            // Set up the ruleset's metadata.
            JBRulesetMetadata memory metadata;
            metadata.reservedPercent = stageConfiguration.splitPercent;
            metadata.cashOutTaxRate = stageConfiguration.cashOutTaxRate;
            metadata.baseCurrency = configuration.baseCurrency;
            metadata.allowOwnerMinting = true; // Allow this contract to auto-mint tokens as the revnet's owner.
            metadata.useDataHookForPay = true; // Call this contract's `beforePayRecordedWith(…)` callback on payments.
            metadata.dataHook = address(this); // This contract is the data hook.
            metadata.metadata = stageConfiguration.extraMetadata;

            // Set up the ruleset.
            rulesetConfigurations[i] = JBRulesetConfig({
                mustStartAtOrAfter: stageConfiguration.startsAtOrAfter,
                duration: stageConfiguration.issuanceCutFrequency,
                weight: stageConfiguration.initialIssuance,
                weightCutPercent: stageConfiguration.issuanceCutPercent,
                approvalHook: IJBRulesetApprovalHook(address(0)),
                metadata: metadata,
                splitGroups: new JBSplitGroup[](0),
                fundAccessLimitGroups: fundAccessLimitGroups
            });

            // Add the stage's properties to the byte-encoded configuration.
            encodedConfiguration = abi.encode(
                encodedConfiguration, _encodedStageConfig({stageConfiguration: stageConfiguration, stageNumber: i})
            );

            // Store the ruleset's start time for the next iteration.
            previousStartTime = stageConfiguration.startsAtOrAfter;
        }
    }

    /// @notice Returns the permissions that the split operator should be granted for a revnet.
    /// @param revnetId The ID of the revnet to get split operator permissions for.
    /// @return allOperatorPermissions The permissions that the split operator should be granted for the revnet,
    /// including both default and custom permissions.
    function _splitOperatorPermissionIndexesOf(uint256 revnetId)
        internal
        view
        returns (uint256[] memory allOperatorPermissions)
    {
        // Keep a reference to the custom split operator permissions.
        uint256[] memory customSplitOperatorPermissionIndexes = _extraOperatorPermissions[revnetId];

        // Make the array that merges the default and custom operator permissions.
        allOperatorPermissions = new uint256[](3 + customSplitOperatorPermissionIndexes.length);
        allOperatorPermissions[0] = JBPermissionIds.SET_SPLIT_GROUPS;
        allOperatorPermissions[1] = JBPermissionIds.SET_BUYBACK_POOL;
        allOperatorPermissions[2] = JBPermissionIds.SET_PROJECT_URI;

        // Copy the custom permissions into the array.
        for (uint256 i; i < customSplitOperatorPermissionIndexes.length; i++) {
            allOperatorPermissions[3 + i] = customSplitOperatorPermissionIndexes[i];
        }
    }

    /// @notice Converts a `uint256` array to a `uint8` array.
    /// @param array The array to convert.
    /// @return result The converted array.
    function _uint256ArrayToUint8Array(uint256[] memory array) internal pure returns (uint8[] memory result) {
        result = new uint8[](array.length);
        for (uint256 i; i < array.length; i++) {
            result[i] = uint8(array[i]);
        }
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Processes the fee from a cash out.
    /// @param context Cash out context passed in by the terminal.
    function afterCashOutRecordedWith(JBAfterCashOutRecordedContext calldata context) external payable {
        // If there's sufficient approval, transfer normally.
        if (context.forwardedAmount.token != JBConstants.NATIVE_TOKEN) {
            return IERC20(context.forwardedAmount.token).safeTransferFrom({
                from: msg.sender,
                to: address(this),
                value: context.forwardedAmount.value
            });
        }

        // Parse the metadata forwarded from the data hook to get the fee terminal.
        // See `beforeCashOutRecordedWith(…)`.
        (IJBTerminal feeTerminal) = abi.decode(context.hookMetadata, (IJBTerminal));

        // Determine how much to pay in `msg.value` (in the native currency).
        uint256 payValue = _beforeTransferTo({
            to: address(feeTerminal),
            token: context.forwardedAmount.token,
            amount: context.forwardedAmount.value
        });

        // Pay the fee.
        // slither-disable-next-line arbitrary-send-eth,unused-return
        try feeTerminal.pay{value: payValue}({
            projectId: FEE_REVNET_ID,
            token: context.forwardedAmount.token,
            amount: context.forwardedAmount.value,
            beneficiary: context.holder,
            minReturnedTokens: 0,
            memo: "",
            metadata: bytes(abi.encodePacked(context.projectId))
        }) {} catch (bytes memory) {
            // Decrease the allowance for the fee terminal if the token is not the native token.
            if (context.forwardedAmount.token != JBConstants.NATIVE_TOKEN) {
                IERC20(context.forwardedAmount.token).safeDecreaseAllowance({
                    spender: address(feeTerminal),
                    requestedDecrease: context.forwardedAmount.value
                });
            }

            // If the fee can't be processed, return the funds to the project.
            payValue = _beforeTransferTo({
                to: msg.sender,
                token: context.forwardedAmount.token,
                amount: context.forwardedAmount.value
            });

            // slither-disable-next-line arbitrary-send-eth
            IJBTerminal(msg.sender).addToBalanceOf{value: payValue}({
                projectId: context.projectId,
                token: context.forwardedAmount.token,
                amount: context.forwardedAmount.value,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes(abi.encodePacked(FEE_REVNET_ID))
            });
        }
    }

    /// @notice Auto-mint a revnet's tokens from a stage for a beneficiary.
    /// @param revnetId The ID of the revnet to auto-mint tokens from.
    /// @param stageId The ID of the stage auto-mint tokens are available from.
    /// @param beneficiary The address to auto-mint tokens to.
    function autoIssueFor(uint256 revnetId, uint256 stageId, address beneficiary) external override {
        // Make sure the stage has started.
        if (CONTROLLER.RULESETS().getRulesetOf(revnetId, stageId).start > block.timestamp) {
            revert REVDeployer_StageNotStarted();
        }

        // Get a reference to the number of tokens to auto-issue.
        uint256 count = amountToAutoIssue[revnetId][stageId][beneficiary];

        // If there's nothing to auto-mint, return.
        if (count == 0) return;

        // Reset the auto-mint amount.
        amountToAutoIssue[revnetId][stageId][beneficiary] = 0;

        // Decrease the amount of unrealized auto-issuance tokens.
        unrealizedAutoIssuanceAmountOf[revnetId] -= count;

        emit AutoIssue({
            revnetId: revnetId,
            stageId: stageId,
            beneficiary: beneficiary,
            count: count,
            caller: _msgSender()
        });

        // Mint the tokens.
        _mintTokensOf({revnetId: revnetId, tokenCount: count, beneficiary: beneficiary});
    }

    /// @notice Launch a revnet, or convert an existing Juicebox project into a revnet.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @return revnetId The ID of the newly created revnet.
    function deployFor(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        override
        returns (uint256)
    {
        // Deploy the revnet.
        return _deployRevnetFor({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });
    }

    /// @notice Deploy new suckers for an existing revnet.
    /// @dev Only the revnet's split operator can deploy new suckers.
    /// @param revnetId The ID of the revnet to deploy suckers for.
    /// @param encodedConfiguration A byte-encoded representation of the revnet's configuration.
    /// See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration
    /// from the `DeployRevnet` event emitted by this contract.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet.
    function deploySuckersFor(
        uint256 revnetId,
        bytes calldata encodedConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        override
        returns (address[] memory suckers)
    {
        // Make sure the caller is the revnet's split operator.
        _checkIfIsSplitOperatorOf({revnetId: revnetId, operator: _msgSender()});

        // Check if the current ruleset allows deploying new suckers.
        if (!allowsDeployingSuckersInCurrentRulesetOf(revnetId)) {
            revert REVDeployer_RulesetDoesNotAllowDeployingSuckers();
        }

        // Deploy the suckers.
        suckers = _deploySuckersFor({
            revnetId: revnetId,
            encodedConfiguration: encodedConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });
    }

    /// @notice Launch a revnet which sells tiered ERC-721s and (optionally) allows croptop posts to its ERC-721 tiers.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @param tiered721HookConfiguration How to set up the tiered ERC-721 hook for the revnet.
    /// @param allowedPosts Restrictions on which croptop posts are allowed on the revnet's ERC-721 tiers.
    /// @return revnetId The ID of the newly created revnet.
    /// @return hook The address of the tiered ERC-721 hook that was deployed for the revnet.
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
        returns (uint256, IJB721TiersHook hook)
    {
        // Deploy the revnet with the specified tiered ERC-721 hook and croptop posting criteria.
        (revnetId, hook) = _deploy721RevnetFor({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            tiered721HookConfiguration: tiered721HookConfiguration,
            allowedPosts: allowedPosts
        });

        return (revnetId, hook);
    }

    /// @notice Change a revnet's split operator.
    /// @dev Only a revnet's current split operator can set a new split operator.
    /// @param revnetId The ID of the revnet to set the split operator of.
    /// @param newSplitOperator The new split operator's address.
    function setSplitOperatorOf(uint256 revnetId, address newSplitOperator) external override {
        // Enforce permissions.
        _checkIfIsSplitOperatorOf({revnetId: revnetId, operator: _msgSender()});

        emit ReplaceSplitOperator({revnetId: revnetId, newSplitOperator: newSplitOperator, caller: _msgSender()});

        // Remove operator permissions from the old split operator.
        _setPermissionsFor({
            account: address(this),
            operator: _msgSender(),
            revnetId: uint56(revnetId),
            permissionIds: new uint8[](0)
        });

        // Set the new split operator.
        _setSplitOperatorOf({revnetId: revnetId, operator: newSplitOperator});
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Logic to be triggered before transferring tokens from this contract.
    /// @param to The address the transfer is going to.
    /// @param token The token being transferred.
    /// @param amount The number of tokens being transferred, as a fixed point number with the same number of decimals
    /// as the token specifies.
    /// @return payValue The value to attach to the transaction being sent.
    function _beforeTransferTo(address to, address token, uint256 amount) internal returns (uint256) {
        // If the token is the native token, no allowance needed.
        if (token == JBConstants.NATIVE_TOKEN) return amount;
        IERC20(token).safeIncreaseAllowance(to, amount);
        return 0;
    }

    /// @notice Configure croptop posting.
    /// @param hook The hook that will be posted to.
    /// @param allowedPosts The type of posts that the revent should allow.
    /// @return flag A flag indicating if posts were configured. Returns false if there were no posts to set up.
    function _configurePostingCriteriaFor(
        address hook,
        REVCroptopAllowedPost[] calldata allowedPosts
    )
        internal
        returns (bool)
    {
        // If there are no posts to allow, return.
        if (allowedPosts.length == 0) return false;

        // Keep a reference to the formatted allowed posts.
        CTAllowedPost[] memory formattedAllowedPosts = new CTAllowedPost[](allowedPosts.length);

        // Iterate through each post to add it to the formatted list.
        for (uint256 i; i < allowedPosts.length; i++) {
            // Set the post being iterated on.
            REVCroptopAllowedPost calldata post = allowedPosts[i];

            // Set the formatted post.
            formattedAllowedPosts[i] = CTAllowedPost({
                hook: hook,
                category: post.category,
                minimumPrice: post.minimumPrice,
                minimumTotalSupply: post.minimumTotalSupply,
                maximumTotalSupply: post.maximumTotalSupply,
                allowedAddresses: post.allowedAddresses
            });
        }

        // Set up the allowed posts in the publisher.
        PUBLISHER.configurePostingCriteriaFor({allowedPosts: formattedAllowedPosts});

        return true;
    }

    /// @notice Deploy a revnet which sells tiered ERC-721s and (optionally) allows croptop posts to its ERC-721 tiers.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @param tiered721HookConfiguration How to set up the tiered ERC-721 hook for the revnet.
    /// @param allowedPosts Restrictions on which croptop posts are allowed on the revnet's ERC-721 tiers.
    /// @return revnetId The ID of the newly created revnet.
    /// @return hook The address of the tiered ERC-721 hook that was deployed for the revnet.
    function _deploy721RevnetFor(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig calldata tiered721HookConfiguration,
        REVCroptopAllowedPost[] calldata allowedPosts
    )
        internal
        returns (uint256, IJB721TiersHook hook)
    {
        // Keep a reference to the revnet ID which was passed in.
        uint256 originalRevnetId = revnetId;

        // If the caller is deploying a new revnet, calculate its ID
        // (which will be 1 greater than the current count).
        if (originalRevnetId == 0) revnetId = PROJECTS.count() + 1;

        // Deploy the tiered ERC-721 hook contract.
        // slither-disable-next-line reentrancy-benign
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: revnetId,
            deployTiersHookConfig: tiered721HookConfiguration.baseline721HookConfiguration,
            salt: keccak256(abi.encode(tiered721HookConfiguration.salt, _msgSender()))
        });

        // Store the tiered ERC-721 hook.
        tiered721HookOf[revnetId] = hook;

        // If specified, give the split operator permission to add and remove tiers.
        if (tiered721HookConfiguration.splitOperatorCanAdjustTiers) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.ADJUST_721_TIERS);
        }

        // If specified, give the split operator permission to set ERC-721 tier metadata.
        if (tiered721HookConfiguration.splitOperatorCanUpdateMetadata) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.SET_721_METADATA);
        }

        // If specified, give the split operator permission to mint ERC-721s (without a payment)
        // from tiers with `allowOwnerMint` set to true.
        if (tiered721HookConfiguration.splitOperatorCanMint) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.MINT_721);
        }

        // If specified, give the split operator permission to increase the discount of a tier.
        if (tiered721HookConfiguration.splitOperatorCanIncreaseDiscountPercent) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.SET_721_DISCOUNT_PERCENT);
        }

        // Set up croptop posting criteria as specified.
        if (_configurePostingCriteriaFor({hook: address(hook), allowedPosts: allowedPosts})) {
            // Give the croptop publisher permission to post new ERC-721 tiers on this contract's behalf.
            _setPermission({
                operator: address(PUBLISHER),
                revnetId: revnetId,
                permissionId: JBPermissionIds.ADJUST_721_TIERS
            });
        }

        _deployRevnetFor({
            revnetId: originalRevnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });

        return (revnetId, hook);
    }

    /// @notice Deploy a revnet, or convert an existing Juicebox project into a revnet.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @return revnetId The ID of the newly created revnet.
    function _deployRevnetFor(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        internal
        returns (uint256)
    {
        // Normalize and encode the configurations.
        (JBRulesetConfig[] memory rulesetConfigurations, bytes memory encodedConfiguration) =
            _makeRulesetConfigurations({configuration: configuration, terminalConfigurations: terminalConfigurations});

        if (revnetId == 0) {
            // If we're deploying a new revnet, launch a Juicebox project for it.
            // slither-disable-next-line reentrancy-benign,reentrancy-events
            revnetId = CONTROLLER.launchProjectFor({
                owner: address(this),
                projectUri: configuration.description.uri,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: ""
            });
        } else {
            // If we're converting an existing Juicebox project into a revnet,
            // transfer the `JBProjects` NFT to this deployer.
            IERC721(PROJECTS).safeTransferFrom({from: PROJECTS.ownerOf(revnetId), to: address(this), tokenId: revnetId});

            // Launch the revnet rulesets for the pre-existing project.
            // slither-disable-next-line unused-return
            CONTROLLER.launchRulesetsFor({
                projectId: revnetId,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: ""
            });
        }

        // Store the cash out delay of the revnet if its stages are already in progress.
        // This prevents cash out liquidity/arbitrage issues for existing revnets which
        // are deploying to a new chain.
        _setCashOutDelayIfNeeded({revnetId: revnetId, firstStageConfig: configuration.stageConfigurations[0]});

        // Deploy the revnet's ERC-20 token.
        // slither-disable-next-line unused-return
        CONTROLLER.deployERC20For({
            projectId: revnetId,
            name: configuration.description.name,
            symbol: configuration.description.ticker,
            salt: keccak256(abi.encode(configuration.description.salt, _msgSender()))
        });

        // If specified, set up the buyback hook.
        if (buybackHookConfiguration.hook != IJBBuybackHook(address(0))) {
            _setupBuybackHookOf(revnetId, buybackHookConfiguration);
        }

        // If specified, set up the loan contract.
        if (configuration.loans != address(0)) {
            _setPermission({
                operator: address(configuration.loans),
                revnetId: revnetId,
                permissionId: JBPermissionIds.USE_ALLOWANCE
            });
            loansOf[revnetId] = configuration.loans;
        }

        // Set up the reserved token split group under the default ruleset (0).
        // This split group sends the revnet's reserved tokens to the split operator,
        // who can allocate splits to other recipients later on.
        CONTROLLER.setSplitGroupsOf({
            projectId: revnetId,
            rulesetId: 0,
            splitGroups: _makeOperatorSplitGroupWith(configuration.splitOperator)
        });

        // Store the auto-issuance amounts.
        _storeAutoIssuanceAmounts({revnetId: revnetId, configuration: configuration});

        // Give the split operator their permissions.
        _setSplitOperatorOf({revnetId: revnetId, operator: configuration.splitOperator});

        // Deploy the suckers (if applicable).
        if (suckerDeploymentConfiguration.salt != bytes32(0)) {
            _deploySuckersFor({
                revnetId: revnetId,
                encodedConfiguration: encodedConfiguration,
                suckerDeploymentConfiguration: suckerDeploymentConfiguration
            });
        }

        emit DeployRevnet({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            rulesetConfigurations: rulesetConfigurations,
            encodedConfiguration: encodedConfiguration,
            caller: _msgSender()
        });

        return revnetId;
    }

    /// @notice Deploy suckers for a revnet.
    /// @param revnetId The ID of the revnet to deploy suckers for.
    /// @param encodedConfiguration A byte-encoded representation of the revnet's configuration.
    /// See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration
    /// from the `DeployRevnet` event emitted by this contract.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet.
    function _deploySuckersFor(
        uint256 revnetId,
        bytes memory encodedConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        internal
        returns (address[] memory suckers)
    {
        // Compose the salt.
        bytes32 salt = keccak256(abi.encode(encodedConfiguration, suckerDeploymentConfiguration.salt));

        emit DeploySuckers({
            revnetId: revnetId,
            salt: salt,
            encodedConfiguration: encodedConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            caller: _msgSender()
        });

        // Deploy the suckers.
        // slither-disable-next-line unused-return
        suckers = SUCKER_REGISTRY.deploySuckersFor({
            projectId: revnetId,
            salt: salt,
            configurations: suckerDeploymentConfiguration.deployerConfigurations
        });
    }

    /// @notice Mints a revnet's tokens.
    /// @param revnetId The ID of the revnet to mint tokens for.
    /// @param tokenCount The number of tokens to mint.
    /// @param beneficiary The address to send the tokens to.
    function _mintTokensOf(uint256 revnetId, uint256 tokenCount, address beneficiary) internal {
        // slither-disable-next-line unused-return
        CONTROLLER.mintTokensOf({
            projectId: revnetId,
            tokenCount: tokenCount,
            beneficiary: beneficiary,
            memo: "",
            useReservedPercent: false
        });
    }

    /// @notice Sets the cash out delay if the revnet's stages are already in progress.
    /// @dev This prevents cash out liquidity/arbitrage issues for existing revnets which
    /// are deploying to a new chain.
    /// @param revnetId The ID of the revnet to set the cash out delay for.
    /// @param firstStageConfig The revnet's first stage.
    function _setCashOutDelayIfNeeded(uint256 revnetId, REVStageConfig calldata firstStageConfig) internal {
        // If this is the first revnet being deployed (with a `startsAtOrAfter` of 0),
        // or if the first stage hasn't started yet, we don't need to set a cash out delay.
        if (firstStageConfig.startsAtOrAfter == 0 || firstStageConfig.startsAtOrAfter >= block.timestamp) return;

        // Calculate the timestamp at which the cash out delay ends.
        uint256 cashOutDelay = block.timestamp + CASH_OUT_DELAY;

        // Store the cash out delay.
        cashOutDelayOf[revnetId] = cashOutDelay;

        emit SetCashOutDelay({revnetId: revnetId, cashOutDelay: cashOutDelay, caller: _msgSender()});
    }

    /// @notice Grants a permission to an address (an "operator").
    /// @param operator The address to give the permission to.
    /// @param revnetId The ID of the revnet to scope the permission for.
    /// @param permissionId The ID of the permission to set. See `JBPermissionIds`.
    function _setPermission(address operator, uint256 revnetId, uint8 permissionId) internal {
        uint8[] memory permissionsIds = new uint8[](1);
        permissionsIds[0] = permissionId;

        // Give the operator the permission.
        _setPermissionsFor({
            account: address(this),
            operator: operator,
            revnetId: revnetId,
            permissionIds: permissionsIds
        });
    }

    /// @notice Grants a permission to an address (an "operator").
    /// @param account The account granting the permission.
    /// @param operator The address to give the permission to.
    /// @param revnetId The ID of the revnet to scope the permission for.
    /// @param permissionIds An array of permission IDs to set. See `JBPermissionIds`.
    function _setPermissionsFor(
        address account,
        address operator,
        uint256 revnetId,
        uint8[] memory permissionIds
    )
        internal
    {
        // Set up the permission data.
        JBPermissionsData memory permissionData =
            JBPermissionsData({operator: operator, projectId: uint56(revnetId), permissionIds: permissionIds});

        // Set the permissions.
        PERMISSIONS.setPermissionsFor({account: account, permissionsData: permissionData});
    }

    /// @notice Give a split operator their permissions.
    /// @dev Only a revnet's current split operator can set a new split operator, by calling `setSplitOperatorOf(…)`.
    /// @param revnetId The ID of the revnet to set the split operator of.
    /// @param operator The new split operator's address.
    function _setSplitOperatorOf(uint256 revnetId, address operator) internal {
        _setPermissionsFor({
            account: address(this),
            operator: operator,
            revnetId: uint56(revnetId),
            permissionIds: _uint256ArrayToUint8Array(_splitOperatorPermissionIndexesOf(revnetId))
        });
    }

    /// @notice Sets up a buyback hook and pools for a revnet.
    /// @param revnetId The ID of the revnet to set up the buyback hook for.
    /// @param buybackHookConfiguration The address of the hook and a list of pools to use for buybacks.
    function _setupBuybackHookOf(uint256 revnetId, REVBuybackHookConfig calldata buybackHookConfiguration) internal {
        // Store the buyback hook.
        buybackHookOf[revnetId] = buybackHookConfiguration.hook;

        for (uint256 i; i < buybackHookConfiguration.poolConfigurations.length; i++) {
            // Set the pool being iterated on.
            REVBuybackPoolConfig calldata poolConfig = buybackHookConfiguration.poolConfigurations[i];

            // Register the pool within the buyback contract.
            // slither-disable-next-line unused-return
            buybackHookConfiguration.hook.setPoolFor({
                projectId: revnetId,
                fee: poolConfig.fee,
                twapWindow: poolConfig.twapWindow,
                twapSlippageTolerance: poolConfig.twapSlippageTolerance,
                terminalToken: poolConfig.token
            });
        }
    }

    /// @notice Stores the auto-issuance amounts for each of a revnet's stages.
    /// @param revnetId The ID of the revnet to store the auto-mint amounts for.
    /// @param configuration The revnet's configuration. See `REVConfig`.
    function _storeAutoIssuanceAmounts(uint256 revnetId, REVConfig calldata configuration) internal {
        // Keep a reference to the total amount of tokens which can be auto-minted.
        uint256 totalUnrealizedAutoIssuanceAmount;

        // Loop through each stage to store its auto-issuance amounts.
        for (uint256 i; i < configuration.stageConfigurations.length; i++) {
            // Set the stage configuration being iterated on.
            REVStageConfig calldata stageConfiguration = configuration.stageConfigurations[i];

            // Loop through each mint to store its amount.
            for (uint256 j; j < stageConfiguration.autoIssuances.length; j++) {
                // Set the mint config being iterated on.
                REVAutoIssuance calldata issuanceConfig = stageConfiguration.autoIssuances[j];

                // If the issuance config is for another chain, skip it.
                if (issuanceConfig.chainId != block.chainid) continue;

                // If there's nothing to auto-mint, continue.
                if (issuanceConfig.count == 0) continue;

                // Make sure the beneficiary is not the zero address.
                if (issuanceConfig.beneficiary == address(0)) revert REVDeployer_AutoIssuanceBeneficiaryZeroAddress();

                emit StoreAutoIssuanceAmount({
                    revnetId: revnetId,
                    stageId: block.timestamp + i,
                    beneficiary: issuanceConfig.beneficiary,
                    count: issuanceConfig.count,
                    caller: _msgSender()
                });

                // If the auto-issuance is for the first stage, or a stage which has already started,
                // mint the tokens right away.
                if (i == 0 || stageConfiguration.startsAtOrAfter <= block.timestamp) {
                    emit AutoIssue({
                        revnetId: revnetId,
                        stageId: block.timestamp + i,
                        beneficiary: issuanceConfig.beneficiary,
                        count: issuanceConfig.count,
                        caller: _msgSender()
                    });

                    // slither-disable-next-line reentrancy-events,reentrancy-no-eth,reentrancy-benign
                    _mintTokensOf({
                        revnetId: revnetId,
                        tokenCount: issuanceConfig.count,
                        beneficiary: issuanceConfig.beneficiary
                    });
                }
                // Otherwise, store the amount of tokens that can be auto-minted on this chain during this stage.
                else {
                    // The first stage ID is stored at this block's timestamp,
                    // and further stage IDs have incrementally increasing IDs
                    // slither-disable-next-line reentrancy-events
                    amountToAutoIssue[revnetId][block.timestamp + i][issuanceConfig.beneficiary] += issuanceConfig.count;

                    // Add to the total unrealized auto-issuance amount.
                    totalUnrealizedAutoIssuanceAmount += issuanceConfig.count;
                }
            }
        }

        // Store the unrealized auto-issuance amount.
        unrealizedAutoIssuanceAmountOf[revnetId] = totalUnrealizedAutoIssuanceAmount;
    }
}
