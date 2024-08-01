// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBSplitHook} from "@bananapus/core/src/interfaces/IJBSplitHook.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBRedemptions} from "@bananapus/core/src/libraries/JBRedemptions.sol";
import {JBSplitGroupIds} from "@bananapus/core/src/libraries/JBSplitGroupIds.sol";
import {JBAfterRedeemRecordedContext} from "@bananapus/core/src/structs/JBAfterRedeemRecordedContext.sol";
import {JBCurrencyAmount} from "@bananapus/core/src/structs/JBCurrencyAmount.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core/src/structs/JBFundAccessLimitGroup.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBRuleset} from "@bananapus/core/src/structs/JBRuleset.sol";
import {JBSplitGroup} from "@bananapus/core/src/structs/JBSplitGroup.sol";
import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {JBBeforeRedeemRecordedContext} from "@bananapus/core/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBRedeemHook} from "@bananapus/core/src/interfaces/IJBRedeemHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBRedeemHookSpecification} from "@bananapus/core/src/structs/JBRedeemHookSpecification.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";

import {REVConfig} from "./../structs/REVConfig.sol";
import {REVLoanSource} from "./../structs/REVLoanSource.sol";
import {IREVBasic} from "./../interfaces/IREVBasic.sol";
import {IREVLoans} from "../interfaces/IREVLoans.sol";
import {REVMintConfig} from "./../structs/REVMintConfig.sol";
import {REVStageConfig} from "./../structs/REVStageConfig.sol";
import {REVBuybackHookConfig} from "./../structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "./../structs/REVBuybackPoolConfig.sol";
import {REVSuckerDeploymentConfig} from "./../structs/REVSuckerDeploymentConfig.sol";

/// @notice `REVBasic` contains core logic for deploying, managing, and operating Revnets.
/// @dev Key features:
/// - `_launchRevnetFor(…)` deploys a new revnet, or converts an existing Juicebox project into one.
/// - `beforePayRecordedWith(…)` triggers a revnet's buyback hook when it is paid.
/// - `beforeRedeemRecordedWith(…)` calculates the fee to be charged on redemptions, and
///   `afterRedeemRecordedWith(…)` processes that fee.
/// - `deploySuckersFor(…)` allows a revnet's split operator to deploy new suckers for an existing revnet.
abstract contract REVBasic is IREVBasic, IJBRulesetDataHook, IJBRedeemHook, IERC721Receiver {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error REVBasic_StageTimesMustIncrease();
    error REVBasic_CashOutDelayNotFinished();
    error REVBasic_StagesRequired();
    error REVBasic_StageNotStarted();
    error REVBasic_Unauthorized();

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The number of seconds until a revnet's participants can cash out, starting from the time when that revnet is deployed to a new network.
    /// - Only applies to existing revnets which are deploying onto a new network.
    /// - Intended to prevent liquidity/arbitrage issues which might arise when an existing revnet has a brand new treasury.
    /// @dev 30 days, in seconds.
    uint256 public constant override CASH_OUT_DELAY = 2_592_000;

    /// @notice The cashout fee (as a fraction out of `JBConstants.MAX_FEE`).
    /// Cashout fees are paid to the revnet with the `FEE_REVNET_ID`.
    /// @dev Fees are charged on cashouts if the cashout tax rate is greater than 0%.
    /// @dev When suckers withdraw funds, they do not pay cashout fees.
    uint256 public constant override FEE = 25; // 2.5%

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The Juicebox project ID of the revnet that receives cashout fees.
    uint256 public immutable override FEE_REVNET_ID;

    /// @notice The controller used to create and manage Juicebox projects for revnets.
    IJBController public immutable override CONTROLLER;

    /// @notice The sucker registry that deploys and tracks suckers for revnets.
    IJBSuckerRegistry public immutable override SUCKER_REGISTRY;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Each revnet's data hook. These data hooks return buyback hook data.
    /// @dev Buyback hooks are a combined data hook/pay hook.
    /// @custom:param revnetId The ID of the revnet to get the buyback hook for.
    mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public override buybackHookOf;

    /// @notice The timestamp of when cashouts will become available to a specific revnet's participants.
    /// @dev Only applies to existing revnets which are deploying onto a new network.
    /// @custom:param revnetId The ID of the revnet to get the cashout delay for.
    mapping(uint256 revnetId => uint256 cashOutDelay) public override cashOutDelayOf;

    /// @notice The number of revnet tokens which can be "auto-minted" (minted without payments)
    /// for a specific beneficiary during a stage. Think of this as a per-stage premint.
    /// @dev These tokens can be minted with `mintFor(…)`.
    /// @custom:param revnetId The ID of the revnet to get the auto-mint amount for.
    /// @custom:param stageId The ID of the stage to get the auto-mint amount for.
    /// @custom:param beneficiary The beneficiary of the auto-mint.
    mapping(uint256 revnetId => mapping(uint256 stageId => mapping(address beneficiary => uint256))) public override
        amountToAutoMint;

    /// @notice The total number of tokens which are available for auto-minting.
    /// @dev These tokens can be claimed with `mintFor(…)`.
    /// @custom:param revnetId The ID of the revnet to get the pending auto-mint amount for.
    mapping(uint256 revnetId => uint256) public override totalPendingAutomintAmountOf;

    /// @notice The loan contract for each revnet.
    /// @dev Revnets can offer loans to their participants, collateralized by their tokens.
    /// Participants can borrow up to the current cashout value of their tokens.
    /// @custom:param revnetId The ID of the revnet to get the loan contract of.
    mapping(uint256 revnetId => address) public override loansOf;

    //*********************************************************************//
    // ------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice A list of `JBPermissonIds` indices to grant to the split operator of a specific revnet.
    /// @dev These should be set in the revnet's deployment process.
    /// @custom:param revnetId The ID of the revnet to get the extra operator permissions for.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 revnetId => uint256[]) internal _extraOperatorPermissions;

    /// @notice The pay hook specifications to use when a specific revnet is paid.
    /// @custom:param revnetId The ID of the revnet to get the pay hook specifications for.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 revnetId => JBPayHookSpecification[] payHooks) internal _payHookSpecificationsOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The pay hook specifications to use when a specific revnet is paid.
    /// @custom:param revnetId The ID of the revnet to get the pay hook specifications for.
    /// @return payHookSpecifications The pay hook specifications.
    function payHookSpecificationsOf(uint256 revnetId)
        external
        view
        override
        returns (JBPayHookSpecification[] memory)
    {
        return _payHookSpecificationsOf[revnetId];
    }

    /// @notice Before a revnet processes an incoming payment, determine the weight and pay hooks to use.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a payment.
    /// @param context Standard Juicebox payment context. See `JBBeforePayRecordedContext`.
    /// @return weight The weight which revnet tokens are minted relative to. This can be used to customize how many tokens get minted by a payment.
    /// @return hookSpecifications Amounts (out of what's being paid in) to be sent to pay hooks instead of being paid into the revnet. Useful for automatically routing funds from a treasury as payments come in.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the specifications provided by the buyback data hook.
        JBPayHookSpecification[] memory buybackHookSpecifications;

        // Keep a reference to the buyback hook.
        IJBRulesetDataHook buybackHook = buybackHookOf[context.projectId];

        // Read the weight and specifications from the buyback data hook.
        // If there's no buyback data hook, use the default weight.
        if (buybackHook != IJBRulesetDataHook(address(0))) {
            (weight, buybackHookSpecifications) = buybackHook.beforePayRecordedWith(context);
        } else {
            weight = context.weight;
        }

        // Is there a buyback hook specification?
        bool usesBuybackHook = buybackHookSpecifications.length != 0;

        // Cache any other pay hooks to use.
        JBPayHookSpecification[] memory storedPayHookSpecifications = _payHookSpecificationsOf[context.projectId];

        // Keep a reference to the number of stored pay hook specifications.
        uint256 numberOfStoredPayHookSpecifications = storedPayHookSpecifications.length;

        // Initialize the returned specification array with enough room to include all of the specifications.
        hookSpecifications =
            new JBPayHookSpecification[](numberOfStoredPayHookSpecifications + (usesBuybackHook ? 1 : 0));

        // Add the stored pay hook specifications.
        for (uint256 i; i < numberOfStoredPayHookSpecifications; i++) {
            hookSpecifications[i] = storedPayHookSpecifications[i];
        }

        // And if we have a buyback hook specification, add it to the end of the array.
        if (usesBuybackHook) hookSpecifications[numberOfStoredPayHookSpecifications] = buybackHookSpecifications[0];
    }

    /// @notice Determine how a redemption from a revnet should be processed.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a redemption.
    /// @dev If a sucker is redeeming, no taxes or fees are imposed.
    /// @param context Standard Juicebox redemption context. See `JBBeforeRedeemRecordedContext`.
    /// @return redemptionRate The redemption rate, which influences the amount of terminal tokens which get reclaimed.
    /// @return redeemCount The number of revnet tokens that are redeemed.
    /// @return totalSupply The total revnet token supply.
    /// @return hookSpecifications The amount of funds and the data to send to redeem hooks (this contract).
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata context)
        external
        view
        override
        returns (uint256 redemptionRate, uint256 redeemCount, uint256 totalSupply, JBRedeemHookSpecification[] memory hookSpecifications)
    {
        // If the redeemer is a sucker, return the full redemption amount without taxes or fees.
        if (_isSuckerOf({revnetId: context.projectId, addr: context.holder})) {
            return (JBConstants.MAX_REDEMPTION_RATE, context.redeemCount, context.totalSupply, hookSpecifications);
        }

        // Enforce the cashout delay.
        if (cashOutDelayOf[context.projectId] > block.timestamp) {
            revert REVBasic_CashOutDelayNotFinished();
        }

        // Get the terminal that will receive the cashout fee.
        IJBTerminal feeTerminal = _directory().primaryTerminalOf(FEE_REVNET_ID, context.surplus.token);

        // If there's no cashout tax (100% redemption rate), or if there's no fee terminal, do not charge a fee.
        if (context.redemptionRate == JBConstants.MAX_REDEMPTION_RATE || address(feeTerminal) == address(0)) {
            return (context.redemptionRate, context.redeemCount, context.totalSupply, hookSpecifications);
        }

        // Get a reference to the number of tokens being used to pay the fee (out of the total being redeemed).
        uint256 feeRedeemCount = mulDiv(context.redeemCount, FEE, JBConstants.MAX_FEE);

        // Assemble a redeem hook specification to invoke `afterRedeemRecordedWith(…)` and process the fee.
        hookSpecifications = new JBRedeemHookSpecification[](1);
        hookSpecifications[0] = JBRedeemHookSpecification({
            hook: IJBRedeemHook(address(this)),
            amount: JBRedemptions.reclaimFrom({
                surplus: context.surplus.value,
                tokensRedeemed: feeRedeemCount,
                totalSupply: context.totalSupply,
                redemptionRate: context.redemptionRate
            }),
            metadata: abi.encode(feeTerminal)
        });

        // Return the amount of tokens to be reclaimed, minus the fee.
        return (context.redemptionRate, context.redeemCount - feeRedeemCount, context.totalSupply, hookSpecifications);
    }

    /// @notice A flag indicating whether an address has permission to mint a revnet's tokens on-demand.
    /// @dev Required by the `IJBRulesetDataHook` interface.
    /// @param revnetId The ID of the revnet to check permissions for.
    /// @param addr The address to check the mint permission of.
    /// @return flag A flag indicating whether the address has permission to mint the revnet's tokens on-demand.
    function hasMintPermissionFor(uint256 revnetId, address addr) external view override returns (bool) {
        // The buyback hook is allowed to mint on the project's behalf.
        return addr == address(buybackHookOf[revnetId]) || addr == loansOf[revnetId]
            || _isSuckerOf({revnetId: revnetId, addr: addr});
    }

    /// @dev Make sure this contract can only receive project NFTs from `JBProjects`.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        // Make sure the 721 received is from the `JBProjects` contract.
        if (msg.sender != address(_projects())) revert();

        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice A flag indicating whether an address is a revnet's split operator.
    /// @param revnetId The ID of the revnet.
    /// @param addr The address to check.
    /// @return flag A flag indicating whether the address is the revnet's split operator.
    function isSplitOperatorOf(uint256 revnetId, address addr) public view override returns (bool) {
        return _permissions().hasPermissions({
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
        return interfaceId == type(IREVBasic).interfaceId || interfaceId == type(IJBRulesetDataHook).interfaceId
            || interfaceId == type(IJBRedeemHook).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller used to launch Juicebox projects which will be revnets.
    /// @param suckerRegistry The registry that deploys and tracks each revnet's suckers.
    /// @param feeRevnetId The Juicebox project ID of the revnet that will receive fees.
    constructor(IJBController controller, IJBSuckerRegistry suckerRegistry, uint256 feeRevnetId) {
        CONTROLLER = controller;
        SUCKER_REGISTRY = suckerRegistry;
        FEE_REVNET_ID = feeRevnetId;

        // Give the sucker registry permission to map tokens.
        _setPermission({operator: address(SUCKER_REGISTRY), revnetId: 0, permissionId: JBPermissionIds.MAP_SUCKER_TOKEN});
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Processes the cashout fee from a redemption.
    /// @param context Redemption context passed in by the terminal.
    function afterRedeemRecordedWith(JBAfterRedeemRecordedContext calldata context) external payable {
        // Only the revnet's payment terminals can access this function.
        if (!_directory().isTerminalOf(context.projectId, IJBTerminal(msg.sender))) {
            revert REVBasic_Unauthorized();
        }

        // Parse the metadata forwarded from the data hook to get the fee terminal.
        // See `beforeRedeemRecordedWith(…)`.
        (IJBTerminal feeTerminal) = abi.decode(context.hookMetadata, (IJBTerminal));

        // Determine how much to pay in `msg.value` (in the native currency).
        uint256 payValue = context.forwardedAmount.token == JBConstants.NATIVE_TOKEN ? context.forwardedAmount.value : 0;

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
            // If the fee can't be processed, return the funds to the project.
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

    // /// @notice Allow the split operat
    // /// @notice Allows a revnet's split operator to deploy new suckers to the revnet after it's deployed.
    // /// @dev Only the revnet's split operator can deploy new suckers.
    // /// @param revnetId The ID of the revnet having new suckers deployed.
    // /// @param encodedConfiguration A bytes representation of the revnet's configuration.
    // /// @param suckerDeploymentConfiguration The specifics about the suckers being deployed.
    // function deploySuckersFor(
    //     uint256 revnetId,
    //     bytes calldata encodedConfiguration,
    //     REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    // )
    //     external
    //     override
    // {
    //     // Enforce permissions.
    //     _checkIfSplitOperatorOf({revnetId: revnetId, operator: msg.sender});

    //     // Compose the salt.
    //     bytes32 salt = keccak256(abi.encode(msg.sender, encodedConfiguration, suckerDeploymentConfiguration.salt));

    //     emit DeploySuckers(revnetId, salt, encodedConfiguration, suckerDeploymentConfiguration, msg.sender);

    //     // Deploy the suckers.
    //     _deploySuckersFor({
    //         revnetId: revnetId,
    //         salt: salt,
    //         configurations: suckerDeploymentConfiguration.deployerConfigurations
    //     });
    // }

    /// @notice Mint tokens from a revnet to a specified beneficiary according to the rules set for the revnet.
    /// @param revnetId The ID of the revnet to mint tokens from.
    /// @param stageId The ID of the stage to mint tokens from.
    /// @param beneficiary The address to mint tokens to.
    function mintFor(uint256 revnetId, uint256 stageId, address beneficiary) external override {
        // Make sure the stage has started.
        if (CONTROLLER.RULESETS().getRulesetOf(revnetId, stageId).start > block.timestamp) {
            revert REVBasic_StageNotStarted();
        }

        // Get a reference to the amount that should be minted.
        uint256 count = amountToAutoMint[revnetId][stageId][beneficiary];

        // Premint tokens to the split operator if needed.
        if (count == 0) return;

        // Reset the mint amount.
        amountToAutoMint[revnetId][stageId][beneficiary] = 0;

        // Decrement the total pending mint amounts.
        totalPendingAutomintAmountOf[revnetId] -= count;

        emit Mint(revnetId, stageId, beneficiary, count, msg.sender);

        _mintTokensOf({revnetId: revnetId, tokenCount: count, beneficiary: beneficiary});
    }

    /// @notice A revnet's operator can replace itself.
    /// @dev Only the revnet's split operator can replace itself.
    /// @param revnetId The ID of the revnet having its operator replaced.
    /// @param newSplitOperator The address of the new split operator.
    function replaceSplitOperatorOf(uint256 revnetId, address newSplitOperator) external override {
        // Enforce permissions.
        if (!isSplitOperatorOf(revnetId, msg.sender)) revert REVBasic_Unauthorized();

        emit ReplaceSplitOperator(revnetId, newSplitOperator, msg.sender);

        // Remove operator permission from the old split operator.
        _setPermissionsFor({
            account: address(this),
            operator: msg.sender,
            revnetId: uint56(revnetId),
            permissionIds: new uint8[](0)
        });

        // Set the new split operator.
        _setSplitOperatorOf({revnetId: revnetId, operator: newSplitOperator});
    }

    //*********************************************************************//
    // --------------------- itnernal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Deploys a revnet with the specified hook information.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param dataHook The address of the data hook.
    /// @param extraHookMetadata Extra info to send to the hook.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @return revnetId The ID of the newly created revnet.
    function _launchRevnetFor(
        uint256 revnetId,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        IJBBuybackHook dataHook,
        uint256 extraHookMetadata,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        internal
        returns (uint256)
    {
        // Normalize the configurations.
        (JBRulesetConfig[] memory rulesetConfigurations, bytes memory encodedConfiguration) =
            _makeRulesetConfigurations(configuration, address(dataHook), extraHookMetadata);

        if (revnetId == 0) {
            // Deploy a juicebox for the revnet.
            // slither-disable-next-line reentrancy-benign,reentrancy-events
            revnetId = CONTROLLER.launchProjectFor({
                owner: address(this),
                projectUri: configuration.description.uri,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: ""
            });
        } else {
            // Transfer the revnet to be owned by this deployer.
            IERC721(CONTROLLER.PROJECTS()).safeTransferFrom(
                CONTROLLER.PROJECTS().ownerOf(revnetId), address(this), revnetId
            );

            // Launch rulesets for a pre-existing juicebox.
            // slither-disable-next-line unused-return
            CONTROLLER.launchRulesetsFor({
                projectId: revnetId,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: ""
            });
        }

        // Store the cash out delay of the revnet if it is in progess. This prevents cashing out from the revnet until
        // the delay
        // is up.
        _setCashOutDelayIfNeeded(revnetId, configuration.stageConfigurations[0]);

        // Issue the network's ERC-20 token.
        // slither-disable-next-line unused-return
        CONTROLLER.deployERC20For({
            projectId: revnetId,
            name: configuration.description.name,
            symbol: configuration.description.ticker,
            salt: configuration.description.salt
        });

        // Setup the buyback hook if needed.
        if (buybackHookConfiguration.hook != IJBBuybackHook(address(0))) {
            _setupBuybackHookOf(revnetId, buybackHookConfiguration);
        }

        // Configure the loan broker if needed.
        if (configuration.loans != address(0)) {
            _setPermission({
                operator: address(configuration.loans),
                revnetId: revnetId,
                permissionId: JBPermissionIds.USE_ALLOWANCE
            });
            loansOf[revnetId] = configuration.loans;
        }

        // Set the operator splits at the default ruleset of 0.
        CONTROLLER.setSplitGroupsOf({
            projectId: revnetId,
            rulesetId: 0,
            splitGroups: _makeOperatorSplitGroupWith(configuration.splitOperator)
        });

        // Store the mint amounts.
        _storeAutomintAmounts(revnetId, configuration);

        // Give the operator its permissions.
        _setSplitOperatorOf({revnetId: revnetId, operator: configuration.splitOperator});

        // Compose the salt.
        bytes32 suckerSalt = suckerDeploymentConfiguration.salt == bytes32(0)
            ? bytes32(0)
            : keccak256(abi.encode(configuration.splitOperator, encodedConfiguration, suckerDeploymentConfiguration.salt));

        // Deploy the suckers if needed.
        if (suckerSalt != bytes32(0)) {
            // slither-disable-next-line unused-return
            SUCKER_REGISTRY.deploySuckersFor({
                projectId: revnetId,
                salt: suckerSalt,
                configurations: suckerDeploymentConfiguration.deployerConfigurations
            });
        }

        emit DeployRevnet(
            revnetId,
            suckerSalt,
            configuration,
            terminalConfigurations,
            buybackHookConfiguration,
            suckerDeploymentConfiguration,
            rulesetConfigurations,
            encodedConfiguration,
            msg.sender
        );

        return revnetId;
    }

    /// @notice Sets the cash out delay if the revnet is in progress.
    /// @param revnetId The ID of the revnet to set the cash out delay for.
    /// @param firstStageConfig The configuration of the first stage of the revnet.
    function _setCashOutDelayIfNeeded(uint256 revnetId, REVStageConfig memory firstStageConfig) internal {
        // If the first stage has a start time in the past, mark the revnet as being in progress.
        if (firstStageConfig.startsAtOrAfter == 0 || firstStageConfig.startsAtOrAfter >= block.timestamp) return;

        // Calculate the delay.
        uint256 cashOutDelay = block.timestamp + CASH_OUT_DELAY;

        // Store the delay.
        cashOutDelayOf[revnetId] = cashOutDelay;

        emit SetCashOutDelay(revnetId, cashOutDelay, msg.sender);
    }

    /// @notice Sets a permission for an operator.
    /// @param operator The operator to give a permission.
    /// @param revnetId The ID of the revnet to set the permission for.
    /// @param permissionId The ID of the permission to set.
    function _setPermission(address operator, uint256 revnetId, uint8 permissionId) internal {
        // Give the address the permission.
        uint8[] memory permissionsIds = new uint8[](1);
        permissionsIds[0] = permissionId;

        // Give the operator permission to change the recipients of the operator's split.
        _setPermissionsFor({
            account: address(this),
            operator: operator,
            revnetId: revnetId,
            permissionIds: permissionsIds
        });
    }

    /// @notice A revnet's operator can replace itself.
    /// @param revnetId The ID of the revnet having its operator replaced.
    /// @param operator The address of the new split operator.
    function _setSplitOperatorOf(uint256 revnetId, address operator) internal {
        // Give the new split operator its permissions.
        _setPermissionsFor({
            account: address(this),
            operator: operator,
            revnetId: uint56(revnetId),
            permissionIds: _uint256ArrayToUint8Array(_splitOperatorPermissionIndexesOf(revnetId))
        });
    }

    /// @notice Stores the amount of tokens that can be minted during each stage from this chain.
    /// @param revnetId The ID of the revnet to which the mints should apply.
    /// @param configuration The data that defines the revnet's characteristics.
    function _storeAutomintAmounts(uint256 revnetId, REVConfig memory configuration) internal {
        // Keep a reference to the number of stages to schedule.
        uint256 numberOfStages = configuration.stageConfigurations.length;

        // Keep a reference to the stage configuration being iterated on.
        REVStageConfig memory stageConfiguration;

        // Keep a reference to the total amount can still be autominted.
        uint256 totalPendingAutomintAmount;

        // Loop through each stage to set up its ruleset configuration.
        for (uint256 i; i < numberOfStages; i++) {
            // Set the stage configuration being iterated on.
            stageConfiguration = configuration.stageConfigurations[i];

            // Keep a reference to the number of mints to store.
            uint256 numberOfMints = stageConfiguration.mintConfigs.length;

            // Keep a reference to the mint config being iterated on.
            REVMintConfig memory mintConfig;

            // Loop through each mint to store its amount.
            for (uint256 j; j < numberOfMints; j++) {
                // Set the mint config being iterated on.
                mintConfig = stageConfiguration.mintConfigs[j];

                // Only deal with mint specification for this chain.
                if (mintConfig.chainId != block.chainid) continue;

                // Mint right away if its the first stage or its any stage that has started.
                if (i == 0 || stageConfiguration.startsAtOrAfter <= block.timestamp) {
                    emit Mint(revnetId, block.timestamp + i, mintConfig.beneficiary, mintConfig.count, msg.sender);

                    // slither-disable-next-line reentrancy-events,reentrancy-no-eth,reentrancy-benign
                    _mintTokensOf({
                        revnetId: revnetId,
                        tokenCount: mintConfig.count,
                        beneficiary: mintConfig.beneficiary
                    });
                }
                // Store the amount of tokens that can be minted during this stage from this chain.
                else {
                    emit StoreMintPotential(
                        revnetId, block.timestamp + i, mintConfig.beneficiary, mintConfig.count, msg.sender
                    );

                    // Stage IDs are indexed incrementally from the timestamp of this transaction.
                    // slither-disable-next-line reentrancy-events
                    amountToAutoMint[revnetId][block.timestamp + i][mintConfig.beneficiary] += mintConfig.count;

                    // Increment the total.
                    totalPendingAutomintAmount += mintConfig.count;
                }
            }
        }

        // Store the total pending mint amounts.
        totalPendingAutomintAmountOf[revnetId] = totalPendingAutomintAmount;
    }

    /// @notice Sets up a buyback hook.
    /// @param revnetId The ID of the revnet to which the buybacks should apply.
    /// @param buybackHookConfiguration Data used to setup pools that'll be used to buyback tokens from if an optimal
    /// price
    /// is presented.
    function _setupBuybackHookOf(uint256 revnetId, REVBuybackHookConfig memory buybackHookConfiguration) internal {
        // Get a reference to the number of pools that need setting up.
        uint256 numberOfPoolsToSetup = buybackHookConfiguration.poolConfigurations.length;

        // Keep a reference to the pool being iterated on.
        REVBuybackPoolConfig memory poolConfig;

        // Store the hook.
        buybackHookOf[revnetId] = buybackHookConfiguration.hook;

        for (uint256 i; i < numberOfPoolsToSetup; i++) {
            // Get a reference to the pool being iterated on.
            poolConfig = buybackHookConfiguration.poolConfigurations[i];

            // Set the pool for the buyback contract.
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

    /// @notice The permissions that the split operator should be granted for a revnet.
    /// @param revnetId The ID of the revnet to check operator permissions for.
    /// @return allOperatorPermissions The permissions that the split operator should be granted for the revnet,
    /// including default and custom permissions.
    function _splitOperatorPermissionIndexesOf(uint256 revnetId)
        internal
        view
        returns (uint256[] memory allOperatorPermissions)
    {
        // Keep a reference to the custom split operator permissions.
        uint256[] memory customSplitOperatorPermissionIndexes = _extraOperatorPermissions[revnetId];

        // Keep a reference to the number of custom permissions.
        uint256 numberOfCustomPermissionIndexes = customSplitOperatorPermissionIndexes.length;

        // Make the array that merges the default operator permissions and the custom ones.
        allOperatorPermissions = new uint256[](4 + numberOfCustomPermissionIndexes);
        allOperatorPermissions[0] = JBPermissionIds.SET_SPLIT_GROUPS;
        allOperatorPermissions[1] = JBPermissionIds.SET_BUYBACK_POOL;
        allOperatorPermissions[2] = JBPermissionIds.SET_PROJECT_URI;
        allOperatorPermissions[3] = JBPermissionIds.DEPLOY_SUCKERS;

        // Copy elements from the custom permissions.
        for (uint256 i; i < numberOfCustomPermissionIndexes; i++) {
            allOperatorPermissions[4 + i] = customSplitOperatorPermissionIndexes[i];
        }
    }

    /// @notice Schedules the initial ruleset for the revnet, and queues all subsequent rulesets that define the stages.
    /// @notice configuration The data that defines the revnet's characteristics.
    /// @notice dataHook The address of the data hook.
    /// @notice extraMetadata Extra info to send to the hook.
    /// @return rulesetConfigurations The ruleset configurations that define the revnet's stages.
    /// @return encodedConfiguration The encoded configuration of the revnet.
    function _makeRulesetConfigurations(
        REVConfig memory configuration,
        address dataHook,
        uint256 extraMetadata
    )
        internal
        view
        returns (JBRulesetConfig[] memory rulesetConfigurations, bytes memory encodedConfiguration)
    {
        // Keep a reference to the number of stages to schedule.
        uint256 numberOfStages = configuration.stageConfigurations.length;

        // Make sure there's at least one stage.
        if (numberOfStages == 0) revert REVBasic_StagesRequired();

        // Each stage is modeled as a ruleset reconfiguration.
        rulesetConfigurations = new JBRulesetConfig[](numberOfStages);

        // Store the base currency in the encoding.
        encodedConfiguration = _encodedConfig(configuration);

        // Keep a reference to the stage configuration being iterated on.
        REVStageConfig memory stageConfiguration;

        // Make the fund access limit groups for the loans.
        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = _makeLoanFundAccessLimits(configuration);

        // Keep a reference to the previous start time.
        uint256 previousStartTime;

        // Loop through each stage to set up its ruleset configuration.
        for (uint256 i; i < numberOfStages; i++) {
            // Set the stage configuration being iterated on.
            stageConfiguration = configuration.stageConfigurations[i];

            // Make sure the start time of this stage is after the previous stage.
            if (stageConfiguration.startsAtOrAfter <= previousStartTime) {
                revert REVBasic_StageTimesMustIncrease();
            }

            // Specify the ruleset.
            rulesetConfigurations[i] = JBRulesetConfig({
                mustStartAtOrAfter: stageConfiguration.startsAtOrAfter,
                duration: stageConfiguration.issuanceDecayFrequency,
                weight: stageConfiguration.initialIssuance,
                decayPercent: stageConfiguration.issuanceDecayPercent,
                approvalHook: IJBRulesetApprovalHook(address(0)),
                metadata: JBRulesetMetadata({
                    reservedPercent: stageConfiguration.splitPercent,
                    redemptionRate: JBConstants.MAX_REDEMPTION_RATE - stageConfiguration.cashOutTaxRate,
                    baseCurrency: configuration.baseCurrency,
                    pausePay: false,
                    pauseCreditTransfers: false,
                    allowOwnerMinting: true, // Allow this contract to auto mint tokens as the network owner.
                    allowSetCustomToken: false,
                    allowTerminalMigration: false,
                    allowSetTerminals: false,
                    allowSetController: false,
                    allowAddAccountingContext: false,
                    allowAddPriceFeed: false,
                    ownerMustSendPayouts: false,
                    holdFees: false,
                    useTotalSurplusForRedemptions: false,
                    useDataHookForPay: true, // Use the buyback data hook.
                    useDataHookForRedeem: false,
                    dataHook: dataHook,
                    metadata: uint16(extraMetadata)
                }),
                splitGroups: new JBSplitGroup[](0),
                fundAccessLimitGroups: fundAccessLimitGroups
            });

            // Append the encoded stage properties.
            encodedConfiguration = abi.encode(
                encodedConfiguration, _encodedStageConfig({stageConfiguration: stageConfiguration, stageNumber: i})
            );

            // Set the previous start time.
            previousStartTime = stageConfiguration.startsAtOrAfter;
        }
    }

    /// @notice Makes the fund access limit groups for the loans.
    /// @param configuration The configuration of the revnet.
    /// @return fundAccessLimitGroups The fund access limit groups for the loans.
    function _makeLoanFundAccessLimits(REVConfig memory configuration)
        internal
        view
        returns (JBFundAccessLimitGroup[] memory fundAccessLimitGroups)
    {
        // Keep a reference to the number of loan access groups there are.
        uint256 numberOfLoanSources = configuration.loanSources.length;

        // Keep a reference to the loan source that'll be iterated on.
        REVLoanSource memory loanSource;

        // Keep a reference to the infinite surplus allowance currency amount.
        JBCurrencyAmount[] memory loanAllowances = new JBCurrencyAmount[](1);
        loanAllowances[0] = JBCurrencyAmount({currency: configuration.baseCurrency, amount: type(uint224).max});

        // Initialize the groups.
        fundAccessLimitGroups = new JBFundAccessLimitGroup[](numberOfLoanSources);

        // Set the fund access  limits for the loans.
        for (uint256 i; i < numberOfLoanSources; i++) {
            // Set the loan access group being iterated on.
            loanSource = configuration.loanSources[i];

            // Set the fund access limits for the loans.
            fundAccessLimitGroups[i] = JBFundAccessLimitGroup({
                terminal: address(loanSource.terminal),
                token: loanSource.token,
                payoutLimits: new JBCurrencyAmount[](0),
                surplusAllowances: loanAllowances
            });
        }
    }

    /// @notice Creates a group of splits that goes entirely to the provided split operator.
    /// @param splitOperator The address to send the entire split amount to.
    /// @return splitGroups The split groups representing operator's split.
    function _makeOperatorSplitGroupWith(address splitOperator)
        internal
        pure
        returns (JBSplitGroup[] memory splitGroups)
    {
        // Send the operator all of the splits. They'll be able to change this later whenever they wish.
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

    /// @notice Encodes a configuration into a hash.
    /// @notice configuration The data that defines the revnet's characteristics.
    /// @return encodedConfiguration The encoded config.
    function _encodedConfig(REVConfig memory configuration) internal pure returns (bytes memory) {
        return abi.encode(
            configuration.baseCurrency,
            configuration.description.name,
            configuration.description.ticker,
            configuration.description.salt
        );
    }

    /// @notice Encodes a stage configuration into a hash.
    /// @notice stageConfiguration The data that defines a revnet's stage characteristics.
    /// @notice stageNumber The number of the stage being encoded.
    /// @return encodedConfiguration The encoded config.
    function _encodedStageConfig(
        REVStageConfig memory stageConfiguration,
        uint256 stageNumber
    )
        internal
        view
        returns (bytes memory encodedConfiguration)
    {
        encodedConfiguration = abi.encode(
            // If no start time is provided for the first stage, use the current block timestamp.
            (stageNumber == 0 && stageConfiguration.startsAtOrAfter == 0)
                ? block.timestamp
                : stageConfiguration.startsAtOrAfter,
            stageConfiguration.splitPercent,
            stageConfiguration.initialIssuance,
            stageConfiguration.issuanceDecayFrequency,
            stageConfiguration.issuanceDecayPercent,
            stageConfiguration.cashOutTaxRate
        );

        // Get a reference to the mint configs.
        uint256 numberOfMintConfigs = stageConfiguration.mintConfigs.length;

        // Add each mint config to the hash.
        for (uint256 i; i < numberOfMintConfigs; i++) {
            encodedConfiguration =
                abi.encode(encodedConfiguration, _encodedMintConfig(stageConfiguration.mintConfigs[i]));
        }
    }

    /// @notice Encodes a mint configuration into a hash.
    /// @notice mintConfig The data that defines how many tokens are allowed to be minted at a stage.
    /// @return encodedMintConfig The encoded mint config.
    function _encodedMintConfig(REVMintConfig memory mintConfig) private pure returns (bytes memory) {
        return abi.encode(mintConfig.chainId, mintConfig.beneficiary, mintConfig.count);
    }

    /// @notice A reference to the controller's permissions contract.
    /// @return permissions The permissions contract.
    function _permissions() internal view returns (IJBPermissions) {
        return IJBPermissioned(address(CONTROLLER)).PERMISSIONS();
    }

    /// @notice Set operator permissions for an account.
    /// @param account The account to set the permissions for.
    /// @param operator The operator to allow.
    /// @param revnetId The ID of the revnet to allow permissions for.
    /// @param permissionIds The permissions to set for the operator.
    function _setPermissionsFor(
        address account,
        address operator,
        uint256 revnetId,
        uint8[] memory permissionIds
    )
        internal
    {
        // Setup the permission data for the new split operator.
        JBPermissionsData memory permissionData =
            JBPermissionsData({operator: operator, projectId: uint56(revnetId), permissionIds: permissionIds});

        // Set the permissions.
        _permissions().setPermissionsFor({account: account, permissionsData: permissionData});
    }

    /// @notice A flag indicating if an address is a sucker for a revnet.
    /// @param revnetId The ID of the revnet to check sucker status for.
    /// @param addr The address to check sucker status for.
    /// @return isSucker A flag indicating if the address is a sucker for the revnet.
    function _isSuckerOf(uint256 revnetId, address addr) internal view returns (bool) {
        return SUCKER_REGISTRY.isSuckerOf(revnetId, addr);
    }

    /// @notice Mints tokens for a revnet.
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

    /// @notice A reference to the controller's directory contract.
    /// @return directory The directory contract.
    function _directory() internal view returns (IJBDirectory) {
        return CONTROLLER.DIRECTORY();
    }

    /// @notice A reference to the controller's projects contract.
    /// @return projects The projects contract.
    function _projects() internal view returns (IJBProjects) {
        return CONTROLLER.PROJECTS();
    }

    /// @notice Converts a uint256 array to a uint8 array.
    /// @param array The array to convert.
    /// @return result The converted array.
    function _uint256ArrayToUint8Array(uint256[] memory array) internal returns (uint8[] memory result) {
        result = new uint8[](array.length);
        for (uint256 i; i < array.length; i++) {
            result[i] = uint8(array[i]);
        }
    }
}
