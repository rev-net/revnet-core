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
import {IREVBasic} from "./../interfaces/IREVBasic.sol";
import {REVMintConfig} from "./../structs/REVMintConfig.sol";
import {REVStageConfig} from "./../structs/REVStageConfig.sol";
import {REVBuybackHookConfig} from "./../structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "./../structs/REVBuybackPoolConfig.sol";
import {REVSuckerDeploymentConfig} from "./../structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic Revnet.
abstract contract REVBasic is IREVBasic, IJBRulesetDataHook, IJBRedeemHook, IERC721Receiver {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error REVBasic_BadStageTimes();
    error REVBasic_ExitDelayInEffect();
    error REVBasic_StageNotStarted();
    error REVBasic_Unauthorized();

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The amount of time from a sucker being deployed to when it can facilitate exits.
    /// @dev 30 days.
    uint256 public constant override EXIT_DELAY = 2_592_000;

    /// @notice Revnets' fee (as a fraction out of `JBConstants.MAX_FEE`).
    /// @dev Fees are charged on redemptions while the redemption rate is less than 100%.
    uint256 public constant override FEE = 25; // 2.5%

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The ID of the revnet that will receive fees.
    uint256 public immutable override FEE_REVNET_ID;

    /// @notice The controller that networks are made from.
    IJBController public immutable override CONTROLLER;

    /// @notice The registry that deploys and tracks each project's suckers.
    IJBSuckerRegistry public immutable override SUCKER_REGISTRY;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The data hook that returns the correct values for the buyback hook of each network.
    /// @custom:param revnetId The ID of the revnet to which the buyback contract applies.
    mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public override buybackHookOf;

    /// @notice The time at which exits from a revnet become allowed.
    /// @custom:param revnetId The ID of the revnet to which the delay applies.
    mapping(uint256 revnetId => uint256 exitDelay) public override exitDelayOf;

    /// @notice The specification of how many tokens are still allowed to be minted at each stage of a revnet.
    /// @custom:param revnetId The ID of the revnet to which the mint applies.
    /// @custom:param stageId The ID of the ruleset to which the mint applies.
    /// @custom:param beneficiary The address that will benefit from the mint.
    mapping(uint256 revnetId => mapping(uint256 stageId => mapping(address beneficiary => uint256))) public override
        allowedMintCountOf;

    //*********************************************************************//
    // ------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice The permissions that the provided operator should be granted if the revnet was deployed with that
    /// intent. This is set once for each revnet when deployed.
    /// @dev This should only be set in the deployment process for each revnet.
    mapping(uint256 => uint256[]) internal _CUSTOM_SPLIT_OPERATOR_PERMISSIONS_INDEXES;

    /// @notice The pay hooks to include during payments to networks.
    /// @custom:param revnetId The ID of the revnet to which the extensions apply.
    mapping(uint256 revnetId => JBPayHookSpecification[] payHooks) internal _payHookSpecificationsOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The pay hooks to include during payments to networks.
    /// @param revnetId The ID of the revnet to which the extensions apply.
    /// @return payHookSpecifications The pay hooks.
    function payHookSpecificationsOf(uint256 revnetId)
        external
        view
        override
        returns (JBPayHookSpecification[] memory)
    {
        return _payHookSpecificationsOf[revnetId];
    }

    /// @notice This function gets called when the revnet receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param context The Juicebox standard network payment context. See
    /// @return weight The weight that network tokens should get minted relative to. This is useful for optionally
    /// customizing how many tokens are issued per payment.
    /// @return hookSpecifications Amount to be sent to pay hooks instead of adding to local balance. Useful for
    /// auto-routing funds from a treasury as payment come in.
    function beforePayRecordedWith(JBBeforePayRecordedContext memory context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the hooks that the buyback hook data hook provides.
        JBPayHookSpecification[] memory buybackHookSpecifications;

        // Keep a reference to the buyback hook.
        IJBRulesetDataHook buybackHook = buybackHookOf[context.projectId];

        // Set the values to be those returned by the buyback hook's data source.
        if (buybackHook != IJBRulesetDataHook(address(0))) {
            (weight, buybackHookSpecifications) = buybackHook.beforePayRecordedWith(context);
        } else {
            weight = context.weight;
        }

        // Check if a buyback hook is used.
        bool usesBuybackHook = buybackHookSpecifications.length != 0;

        // Cache any other pay hooks to use.
        JBPayHookSpecification[] memory storedPayHookSpecifications = _payHookSpecificationsOf[context.projectId];

        // Keep a reference to the number of pay hooks.
        uint256 numberOfStoredPayHookSpecifications = storedPayHookSpecifications.length;

        // Each hook specification must run, plus the buyback hook if provided.
        hookSpecifications =
            new JBPayHookSpecification[](numberOfStoredPayHookSpecifications + (usesBuybackHook ? 1 : 0));

        // Add the other expected pay hooks.
        for (uint256 i; i < numberOfStoredPayHookSpecifications; i++) {
            hookSpecifications[i] = storedPayHookSpecifications[i];
        }

        // Add the buyback hook as the last element.
        if (usesBuybackHook) hookSpecifications[numberOfStoredPayHookSpecifications] = buybackHookSpecifications[0];
    }

    /// @notice Determines how much to redeem.
    /// @dev If a sucker is redeeming, there should be no tax imposed.
    /// @dev Charge a fee on redemptions if there is an exit tax.
    /// @param context The redemption context passed to this contract by the `redeemTokensOf(...)` function.
    /// @return redemptionRate The redemption rate influencing the reclaim amount.
    /// @return redeemCount The amount of tokens that should be considered redeemed.
    /// @return totalSupply The total amount of tokens that are considered to be existing.
    /// @return hookSpecifications The amount and data to send to redeem hooks (this contract) instead of returning to
    /// the beneficiary.
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata context)
        external
        view
        override
        returns (uint256, uint256, uint256, JBRedeemHookSpecification[] memory hookSpecifications)
    {
        // If the holder is a sucker, do not impose a tax.
        if (SUCKER_REGISTRY.isSuckerOf({projectId: context.projectId, suckerAddress: context.holder})) {
            return (JBConstants.MAX_REDEMPTION_RATE, context.redeemCount, context.totalSupply, hookSpecifications);
        }

        // If there's an exit delay, do not allow exits until the delay has passed.
        if (exitDelayOf[context.projectId] > block.timestamp) {
            revert REVBasic_ExitDelayInEffect();
        }

        // Get the terminal that'll receive the fee if one wasn't provided.
        IJBTerminal feeTerminal = _directory().primaryTerminalOf(FEE_REVNET_ID, context.surplus.token);

        // Do not charge a fee if the redemption rate is 100% or if there isn't a fee terminal.
        if (context.redemptionRate == JBConstants.MAX_REDEMPTION_RATE || address(feeTerminal) == address(0)) {
            return (context.redemptionRate, context.redeemCount, context.totalSupply, hookSpecifications);
        }

        // Get a reference to the amount of tokens that are used to cover the fee.
        uint256 feeRedeemCount = mulDiv(context.redeemCount, FEE, JBConstants.MAX_FEE);

        uint256 amount = JBRedemptions.reclaimFrom({
            surplus: context.surplus.value,
            tokensRedeemed: feeRedeemCount,
            totalSupply: context.totalSupply,
            redemptionRate: context.redemptionRate
        });

        // Keep a reference to the hook specifications that invokes this hook to process the fee.
        hookSpecifications = new JBRedeemHookSpecification[](1);
        hookSpecifications[0] = JBRedeemHookSpecification({
            hook: IJBRedeemHook(address(this)),
            amount: amount,
            metadata: abi.encode(feeTerminal)
        });

        // Return the reclaimed amount with the fee charged.
        return (context.redemptionRate, context.redeemCount - feeRedeemCount, context.totalSupply, hookSpecifications);
    }

    /// @notice Required by the IJBRulesetDataHook interfaces.
    /// @param revnetId The ID of the revnet to check permissions for.
    /// @param addr The address to check if has permissions.
    /// @return flag The flag indicating if the address has permissions to mint on the revnet's behalf.
    function hasMintPermissionFor(uint256 revnetId, address addr) external view override returns (bool) {
        // The buyback hook is allowed to mint on the project's behalf.
        if (addr == address(buybackHookOf[revnetId])) return true;

        // Get a reference to the revnet's suckers.
        address[] memory suckers = SUCKER_REGISTRY.suckersOf(revnetId);

        // Keep a reference to the number of suckers there are.
        uint256 numberOfSuckers = suckers.length;

        // The suckers are allowed to mint on the project's behalf.
        for (uint256 i; i < numberOfSuckers; i++) {
            if (addr == suckers[i]) return true;
        }

        // No other contract has minting permissions.
        return false;
    }

    /// @dev Make sure only mints can be received.
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata data
    )
        external
        view
        returns (bytes4)
    {
        data;
        tokenId;
        operator;

        // Make sure the 721 received is the JBProjects contract.
        if (msg.sender != address(_projects())) revert();

        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice A flag indicating if a given address is the revnets split operator.
    /// @param revnetId The ID of the revnet to check the split operator for.
    /// @param addr The address to check if is the split operator.
    /// @return flag The flag indicating if the address is the split operator.
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
    /// @dev See {IERC165-supportsInterface}.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4) public view virtual override returns (bool) {
        return false;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller that revnets are made from.
    /// @param suckerRegistry The registry that deploys and tracks each project's suckers.
    /// @param feeRevnetId The ID of the revnet that will receive fees.
    constructor(IJBController controller, IJBSuckerRegistry suckerRegistry, uint256 feeRevnetId) {
        CONTROLLER = controller;
        SUCKER_REGISTRY = suckerRegistry;
        FEE_REVNET_ID = feeRevnetId;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Processes the fee for the redemption.
    /// @param context The redemption context passed in by the terminal.
    function afterRedeemRecordedWith(JBAfterRedeemRecordedContext calldata context) external payable {
        // Make sure only the project's payment terminals can access this function.
        if (!_directory().isTerminalOf(context.projectId, IJBTerminal(msg.sender))) {
            revert REVBasic_Unauthorized();
        }

        // Parse the metadata forwarded from the data hook to get the fee terminal.
        (IJBTerminal feeTerminal) = abi.decode(context.hookMetadata, (IJBTerminal));

        // Keep a reference to the amount that'll be paid in the native currency.
        uint256 payValue = context.forwardedAmount.token == JBConstants.NATIVE_TOKEN ? context.forwardedAmount.value : 0;

        // Send the fee.
        try feeTerminal.pay{value: payValue}({
            projectId: FEE_REVNET_ID,
            token: context.forwardedAmount.token,
            amount: context.forwardedAmount.value,
            beneficiary: context.holder,
            minReturnedTokens: 0,
            memo: "",
            metadata: bytes(abi.encodePacked(context.projectId))
        }) {} catch (bytes memory) {
            // Return funds to the project if the fee couldn't be processed.
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

    /// @notice Allow the split operat
    /// @notice Allows a revnet's split operator to deploy new suckers to the revnet after it's deployed.
    /// @dev Only the revnet's split operator can deploy new suckers.
    /// @param revnetId The ID of the revnet having new suckers deployed.
    /// @param encodedConfiguration A bytes representation of the revnet's configuration.
    /// @param suckerDeploymentConfiguration The specifics about the suckers being deployed.
    function deploySuckersFor(
        uint256 revnetId,
        bytes memory encodedConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        external
        override
    {
        // Enforce permissions.
        if (!isSplitOperatorOf(revnetId, msg.sender)) revert REVBasic_Unauthorized();

        // Compose the salt.
        bytes32 salt = keccak256(abi.encode(msg.sender, encodedConfiguration, suckerDeploymentConfiguration.salt));

        // Deploy the suckers.
        _deploySuckersFor({
            revnetId: revnetId,
            salt: salt,
            configurations: suckerDeploymentConfiguration.deployerConfigurations
        });

        emit DeploySuckers(revnetId, salt, encodedConfiguration, suckerDeploymentConfiguration, msg.sender);
    }

    /// @notice Mint tokens from a revnet to a specified beneficiary according to the rules set for the revnet.
    /// @param revnetId The ID of the revnet to mint tokens from.
    /// @param stageId The ID of the stage to mint tokens from.
    /// @param beneficiary The address to mint tokens to.
    function mintFor(uint256 revnetId, uint256 stageId, address beneficiary) external override {
        // Get a reference to the revnet's current stage.
        JBRuleset memory stage = CONTROLLER.RULESETS().getRulesetOf(revnetId, stageId);

        // Make sure the stage has started.
        if (stage.start > block.timestamp) revert REVBasic_StageNotStarted();

        // Get a reference to the amount that should be minted.
        uint256 count = allowedMintCountOf[revnetId][stage.id][beneficiary];

        // Premint tokens to the split operator if needed.
        if (count == 0) return;

        // Reset the mint amount.
        allowedMintCountOf[revnetId][stageId][beneficiary] = 0;

        CONTROLLER.mintTokensOf({
            projectId: revnetId,
            tokenCount: count,
            beneficiary: beneficiary,
            memo: "",
            useReservedRate: false
        });

        emit Mint(revnetId, stage.id, beneficiary, count, msg.sender);
    }

    /// @notice A revnet's operator can replace itself.
    /// @dev Only the revnet's split operator can replace itself.
    /// @param revnetId The ID of the revnet having its operator replaced.
    /// @param newSplitOperator The address of the new split operator.
    function replaceSplitOperatorOf(uint256 revnetId, address newSplitOperator) external override {
        /// Make sure the message sender is the current split operator.
        if (!isSplitOperatorOf(revnetId, msg.sender)) revert REVBasic_Unauthorized();

        // Setup the permission data for the old split operator.
        JBPermissionsData memory permissionData =
            JBPermissionsData({operator: msg.sender, projectId: uint56(revnetId), permissionIds: new uint8[](0)});

        // Remove operator permission from the old split operator.
        _permissions().setPermissionsFor({account: address(this), permissionsData: permissionData});

        // Set the new split operator.
        _setSplitOperatorOf({revnetId: revnetId, operator: newSplitOperator});

        emit ReplaceSplitOperator(revnetId, newSplitOperator, msg.sender);
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
        (JBRulesetConfig[] memory rulesetConfigurations, bytes memory encodedConfiguration, bool isInProgress) =
            _makeRulesetConfigurations(configuration, address(dataHook), extraHookMetadata);

        if (revnetId == 0) {
            // Deploy a juicebox for the revnet.
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
            CONTROLLER.launchRulesetsFor({
                projectId: revnetId,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: ""
            });
        }

        // Store the exit delay of the revnet if it is in progess. This prevents exits from the revnet until the delay
        // is up.
        if (isInProgress) {
            exitDelayOf[revnetId] = block.timestamp + EXIT_DELAY;
        }

        // Issue the network's ERC-20 token.
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

        // Set the operator splits at the default ruleset of 0.
        CONTROLLER.setSplitGroupsOf({
            projectId: revnetId,
            rulesetId: 0,
            splitGroups: _makeOperatorSplitGroupWith(configuration.splitOperator)
        });

        // Store the mint amounts.
        _storeMintAmounts(revnetId, configuration);

        // Give the operator its permissions.
        _setSplitOperatorOf({revnetId: revnetId, operator: configuration.splitOperator});

        // Give the sucker registry permission to map tokens.
        uint8[] memory registryPermissions = new uint8[](1);
        registryPermissions[0] = JBPermissionIds.MAP_SUCKER_TOKEN;

        // Give the sucker registry permission to map tokens.
        JBPermissionsData memory permissionsData = JBPermissionsData({
            operator: address(SUCKER_REGISTRY),
            projectId: uint56(revnetId),
            permissionIds: registryPermissions
        });

        // Give the operator permission to change the recipients of the operator's split.
        _permissions().setPermissionsFor({account: address(this), permissionsData: permissionsData});

        // Compose the salt.
        bytes32 salt = keccak256(abi.encode(msg.sender, encodedConfiguration, suckerDeploymentConfiguration.salt));

        // Deploy the suckers if needed.
        if (suckerDeploymentConfiguration.salt != bytes32(0)) {
            _deploySuckersFor({
                revnetId: revnetId,
                salt: salt,
                configurations: suckerDeploymentConfiguration.deployerConfigurations
            });
        }

        emit DeployRevnet(
            revnetId,
            salt,
            configuration,
            terminalConfigurations,
            buybackHookConfiguration,
            suckerDeploymentConfiguration,
            rulesetConfigurations,
            encodedConfiguration,
            isInProgress,
            msg.sender
        );

        return revnetId;
    }

    /// @notice A revnet's operator can replace itself.
    /// @param revnetId The ID of the revnet having its operator replaced.
    /// @param operator The address of the new split operator.
    function _setSplitOperatorOf(uint256 revnetId, address operator) internal {
        // Keep a reference to the split operator permission indexes.
        uint256[] memory splitOperatorPermissionIndexes = _splitOperatorPermissionIndexesOf(revnetId);

        // Keep a reference to how many split operator permissions there are.
        uint256 numberOfSplitOperatorPermissionIndexes = splitOperatorPermissionIndexes.length;

        // Keep a reference to an array where downcast permissions will go.
        uint8[] memory downcastSplitOperatorPermissionIndexes = new uint8[](numberOfSplitOperatorPermissionIndexes);

        // Downcast each permission.
        for (uint256 i; i < numberOfSplitOperatorPermissionIndexes; i++) {
            downcastSplitOperatorPermissionIndexes[i] = uint8(splitOperatorPermissionIndexes[i]);
        }

        // Setup the permission data for the new split operator.
        JBPermissionsData memory permissionData = JBPermissionsData({
            operator: operator,
            projectId: uint56(revnetId),
            permissionIds: downcastSplitOperatorPermissionIndexes
        });

        // Give the new split operator its permissions.
        _permissions().setPermissionsFor({account: address(this), permissionsData: permissionData});
    }

    /// @notice Stores the amount of tokens that can be minted during each stage from this chain.
    /// @param revnetId The ID of the revnet to which the mints should apply.
    /// @param configuration The data that defines the revnet's characteristics.
    function _storeMintAmounts(uint256 revnetId, REVConfig memory configuration) internal {
        // Keep a reference to the number of stages to schedule.
        uint256 numberOfStages = configuration.stageConfigurations.length;

        // Keep a reference to the stage configuration being iterated on.
        REVStageConfig memory stageConfiguration;

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
                    CONTROLLER.mintTokensOf({
                        projectId: revnetId,
                        tokenCount: mintConfig.count,
                        beneficiary: mintConfig.beneficiary,
                        memo: "",
                        useReservedRate: false
                    });
                    emit Mint(revnetId, block.timestamp + i, mintConfig.beneficiary, mintConfig.count, msg.sender);
                }
                // Store the amount of tokens that can be minted during this stage from this chain.
                else {
                    // Stage IDs are indexed incrementally from the timestamp of this transaction.
                    allowedMintCountOf[revnetId][block.timestamp + i][mintConfig.beneficiary] += mintConfig.count;

                    emit StoreMintPotential(
                        revnetId, block.timestamp + i, mintConfig.beneficiary, mintConfig.count, msg.sender
                    );
                }
            }
        }
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

        for (uint256 i; i < numberOfPoolsToSetup; i++) {
            // Get a reference to the pool being iterated on.
            poolConfig = buybackHookConfiguration.poolConfigurations[i];

            // Set the pool for the buyback contract.
            buybackHookConfiguration.hook.setPoolFor({
                projectId: revnetId,
                fee: poolConfig.fee,
                twapWindow: poolConfig.twapWindow,
                twapSlippageTolerance: poolConfig.twapSlippageTolerance,
                terminalToken: poolConfig.token
            });
        }

        // Store the hook.
        buybackHookOf[revnetId] = buybackHookConfiguration.hook;
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
        uint256[] memory customSplitOperatorPermissionIndexes = _CUSTOM_SPLIT_OPERATOR_PERMISSIONS_INDEXES[revnetId];

        // Keep a reference to the number of custom permissions.
        uint256 numberOfCustomPermissionIndexes = customSplitOperatorPermissionIndexes.length;

        // Make the array that merges the default operator permissions and the custom ones.
        allOperatorPermissions = new uint256[](3 + numberOfCustomPermissionIndexes);
        allOperatorPermissions[0] = JBPermissionIds.SET_SPLIT_GROUPS;
        allOperatorPermissions[1] = JBPermissionIds.SET_BUYBACK_POOL;
        allOperatorPermissions[2] = JBPermissionIds.SET_PROJECT_URI;

        // Copy elements from the custom permissions.
        for (uint256 i; i < numberOfCustomPermissionIndexes; i++) {
            allOperatorPermissions[3 + i] = customSplitOperatorPermissionIndexes[i];
        }
    }

    /// @notice Schedules the initial ruleset for the revnet, and queues all subsequent rulesets that define the stages.
    /// @notice configuration The data that defines the revnet's characteristics.
    /// @notice dataHook The address of the data hook.
    /// @notice extraMetadata Extra info to send to the hook.
    /// @return rulesetConfigurations The ruleset configurations that define the revnet's stages.
    /// @return encodedConfiguration The encoded configuration of the revnet.
    /// @return isInProgress Whether the revnet is in progress or not.
    function _makeRulesetConfigurations(
        REVConfig memory configuration,
        address dataHook,
        uint256 extraMetadata
    )
        internal
        view
        returns (JBRulesetConfig[] memory rulesetConfigurations, bytes memory encodedConfiguration, bool isInProgress)
    {
        // Keep a reference to the number of stages to schedule.
        uint256 numberOfStages = configuration.stageConfigurations.length;

        // Each stage is modeled as a ruleset reconfiguration.
        rulesetConfigurations = new JBRulesetConfig[](numberOfStages);

        // Store the base currency in the encoding.
        encodedConfiguration = _encodedConfig(configuration);

        // Keep a reference to the stage configuration being iterated on.
        REVStageConfig memory stageConfiguration;

        // Keep a reference to the previous start time.
        uint256 previousStartTime;

        // Loop through each stage to set up its ruleset configuration.
        for (uint256 i; i < numberOfStages; i++) {
            // Set the stage configuration being iterated on.
            stageConfiguration = configuration.stageConfigurations[i];

            // Make sure the start time of this stage is after the previous stage.
            if (stageConfiguration.startsAtOrAfter <= previousStartTime) {
                revert REVBasic_BadStageTimes();
            }

            rulesetConfigurations[i].mustStartAtOrAfter = stageConfiguration.startsAtOrAfter;
            rulesetConfigurations[i].duration = stageConfiguration.priceIncreaseFrequency;
            // Set the initial issuance for the first ruleset, otherwise pass 0 to inherit from the previous
            // ruleset.
            rulesetConfigurations[i].weight = uint112(mulDiv(1, 10 ** 18, stageConfiguration.initialPrice));
            rulesetConfigurations[i].decayRate = stageConfiguration.priceIncreasePercentage;
            rulesetConfigurations[i].approvalHook = IJBRulesetApprovalHook(address(0));
            rulesetConfigurations[i].metadata = JBRulesetMetadata({
                reservedRate: stageConfiguration.splitPercent,
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE - stageConfiguration.cashOutTaxIntensity,
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
                useDataHookForPay: true, // Use the buyback hook data source.
                useDataHookForRedeem: false,
                dataHook: dataHook,
                metadata: uint16(extraMetadata)
            });

            // If the first stage has a start time in the past, mark the revnet as being in progress.
            if (
                i == 0 && stageConfiguration.startsAtOrAfter != 0
                    && stageConfiguration.startsAtOrAfter < block.timestamp
            ) {
                isInProgress = true;
            }

            // Append the encoded stage properties.
            encodedConfiguration = abi.encode(
                encodedConfiguration, _encodedStageConfig({stageConfiguration: stageConfiguration, stageNumber: i})
            );

            // Set the previous start time.
            previousStartTime = stageConfiguration.startsAtOrAfter;
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
        // Package the reserved token splits.
        splitGroups = new JBSplitGroup[](1);

        // Make the splits.

        // Make a new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory splits = new JBSplit[](1);

        // Send the operator all of the splits. They'll be able to change this later whenever they wish.
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(splitOperator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Set the item in the splits group.
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
            stageConfiguration.initialPrice,
            stageConfiguration.priceIncreaseFrequency,
            stageConfiguration.priceIncreasePercentage,
            stageConfiguration.cashOutTaxIntensity
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

    /// @notice Deploy suckers for a revnet.
    /// @param revnetId The ID of the revnet to deploy suckers for.
    /// @param salt The salt to use for the deployment.
    /// @param configurations The configurations that specify the deployment.
    function _deploySuckersFor(
        uint256 revnetId,
        bytes32 salt,
        JBSuckerDeployerConfig[] memory configurations
    )
        internal
    {
        SUCKER_REGISTRY.deploySuckersFor({projectId: revnetId, salt: salt, configurations: configurations});
    }
}
