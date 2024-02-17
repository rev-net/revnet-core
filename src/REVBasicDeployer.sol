// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBSplitHook} from "@bananapus/core/src/interfaces/IJBSplitHook.sol";
import {IJBToken} from "@bananapus/core/src/interfaces/IJBToken.sol";
import {IJBPayHook} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {JBPermissionIds} from "@bananapus/core/src/libraries/JBPermissionIds.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core/src/libraries/JBSplitGroupIds.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBSplitGroup} from "@bananapus/core/src/structs/JBSplitGroup.sol";
import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {JBBeforeRedeemRecordedContext} from "@bananapus/core/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBRedeemHookSpecification} from "@bananapus/core/src/structs/JBRedeemHookSpecification.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {JBBuybackPermissionIds} from "@bananapus/buyback-hook/src/libraries/JBBuybackPermissionIds.sol";
import {BPTokenConfig} from "@bananapus/suckers/src/structs/BPTokenConfig.sol";
import {IBPSucker} from "@bananapus/suckers/src/interfaces/IBPSucker.sol";

import {IREVBasicDeployer} from "./interfaces/IREVBasicDeployer.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVStageConfig} from "./structs/REVStageConfig.sol";
import {REVSuckerDeployerConfig} from "./structs/REVSuckerDeployerConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "./structs/REVBuybackPoolConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";

/// @notice A contract that facilitates deploying a basic Revnet.
contract REVBasicDeployer is ERC165, IREVBasicDeployer, IJBRulesetDataHook, IERC721Receiver {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error REVBasicDeployer_Unauthorized();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The controller that networks are made from.
    IJBController public immutable CONTROLLER;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The data hook that returns the correct values for the buyback hook of each network.
    /// @custom:param revnetId The ID of the revnet to which the buyback contract applies.
    mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public buybackHookOf;

    /// @notice The suckers that are used to move tokens between chains.
    /// @custom:param revnetId The ID of the revnet to which the sucker contracts apply.
    mapping(uint256 revnetId => IBPSucker[] suckers) public suckersOf;

    //*********************************************************************//
    // ------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice The permissions that the provided operator should be granted. This is set once in the constructor
    /// to contain only the SET_SPLITS operation.
    /// @dev This should only be set in the constructor.
    uint256[] internal _OPERATOR_PERMISSIONS_INDEXES;

    /// @notice The pay hooks to include during payments to networks.
    /// @custom:param revnetId The ID of the revnet to which the extensions apply.
    mapping(uint256 revnetId => JBPayHookSpecification[] payHooks) internal _payHookSpecificationsOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The pay hooks to include during payments to networks.
    /// @param revnetId The ID of the revnet to which the extensions apply.
    /// @return payHookSpecifications The pay hooks.
    function payHookSpecificationsOf(uint256 revnetId) external view returns (JBPayHookSpecification[] memory) {
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
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        virtual
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the hooks that the buyback hook data hook provides.
        JBPayHookSpecification[] memory buybackHookSpecifications;

        // // Set the values to be those returned by the buyback hook's data source.
        (weight, buybackHookSpecifications) = buybackHookOf[context.projectId].beforePayRecordedWith(context);

        // Check if a buyback hook is used.
        bool usesBuybackHook = buybackHookSpecifications.length != 0;

        // Cache any other pay hooks to use.
        JBPayHookSpecification[] memory storedPayHookSpecifications = _payHookSpecificationsOf[context.projectId];

        // Cache any suckers to use.
        IBPSucker[] memory suckers = suckersOf[context.projectId];

        // Keep a reference to the number of pay hooks.
        uint256 numberOfStoredPayHookSpecifications = storedPayHookSpecifications.length;

        // Keep a reference to the number of suckers.
        uint256 numberOfSuckers = suckers.length;

        // Each hook specification must run, plus the buyback hook if provided.
        hookSpecifications = new JBPayHookSpecification[](
            numberOfStoredPayHookSpecifications + numberOfSuckers + (usesBuybackHook ? 1 : 0)
        );

        // Add the other expected pay hooks.
        for (uint256 i; i < numberOfStoredPayHookSpecifications; i++) {
            hookSpecifications[i] = storedPayHookSpecifications[i];
        }

        // Add the suckers.
        for (uint256 i; i < numberOfSuckers; i++) {
            hookSpecifications[numberOfStoredPayHookSpecifications + i] =
                JBPayHookSpecification({hook: IJBPayHook(address(suckers[i])), amount: 0, metadata: bytes("")});
        }

        // Add the buyback hook as the last element.
        if (usesBuybackHook) hookSpecifications[numberOfStoredPayHookSpecifications] = buybackHookSpecifications[0];
    }

    /// @notice This function is never called, it needs to be included to adhere to the interface.
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata)
        external
        view
        virtual
        override
        returns (uint256, JBRedeemHookSpecification[] memory specifications)
    {
        return (0, specifications);
    }

    /// @notice Required by the IJBRulesetDataHook interfaces.
    /// @param revnetId The ID of the revnet to check permissions for.
    /// @param addr The address to check if has permissions.
    /// @return flag The flag indicating if the address has permissions to mint on the revnet's behalf.
    function hasMintPermissionFor(uint256 revnetId, address addr) external view returns (bool) {
        // The buyback hook is allowed to mint on the project's behalf.
        if (addr == address(buybackHookOf[revnetId])) return true;

        // Get a reference to the revnet's suckers.
        IBPSucker[] memory suckers = suckersOf[revnetId];

        // Keep a reference to the number of suckers there are.
        uint256 numberOfSuckers = suckers.length;

        // The suckers are allowed to mint on the project's behalf.
        for (uint256 i; i < numberOfSuckers; i++) {
            if (addr == address(suckers[i])) return true;
        }

        // No other contract has minting permissions.
        return false;
    }

    /// @dev Make sure only mints can be received.
    function onERC721Received(
        address operator,
        address from,
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
        if (msg.sender != address(CONTROLLER.PROJECTS())) revert();
        // Make sure the 721 is being received as a mint.
        if (from != address(0)) revert();
        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IJBRulesetDataHook).interfaceId || super.supportsInterface(interfaceId);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller that revnets are made from.
    constructor(IJBController controller) {
        CONTROLLER = controller;
        _OPERATOR_PERMISSIONS_INDEXES.push(JBPermissionIds.SET_SPLITS);
        _OPERATOR_PERMISSIONS_INDEXES.push(JBBuybackPermissionIds.SET_POOL_PARAMS);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice A revnet's operator can replace itself.
    /// @param revnetId The ID of the revnet having its operator replaced.
    /// @param newOperator The address of the new operator.
    function replaceOperatorOf(uint256 revnetId, address newOperator) external {
        /// Make sure the message sender is the current operator.
        if (
            !IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().hasPermissions({
                operator: msg.sender,
                account: address(this),
                projectId: revnetId,
                permissionIds: _OPERATOR_PERMISSIONS_INDEXES
            })
        ) revert REVBasicDeployer_Unauthorized();

        // Remove operator permission from the old operator.
        IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({operator: msg.sender, projectId: revnetId, permissionIds: new uint256[](0)})
        });

        // Give the new operator permission to change the recipients of the operator's split.
        IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: newOperator,
                projectId: revnetId,
                permissionIds: _OPERATOR_PERMISSIONS_INDEXES
            })
        });
    }

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Deploy a basic revnet.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param projectUri The metadata URI containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @return revnetId The ID of the newly created revnet.
    function deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory projectUri,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        public
        override
        returns (uint256 revnetId)
    {
        // Deploy main revnet.
        revnetId = _deployRevnetWith({
            name: name,
            symbol: symbol,
            projectUri: projectUri,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: 0,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });
    }

    //*********************************************************************//
    // --------------------- itnernal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Deploys a revnet with the specified hook information.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param projectUri The metadata URI containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param dataHook The address of the data hook.
    /// @param extraHookMetadata Extra info to send to the hook.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    /// @return revnetId The ID of the newly created revnet.
    function _deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory projectUri,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        IJBBuybackHook dataHook,
        uint256 extraHookMetadata,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        internal
        virtual
        returns (uint256 revnetId)
    {
        // Deploy a juicebox for the revnet.
        revnetId = CONTROLLER.launchProjectFor({
            owner: address(this),
            projectUri: projectUri,
            rulesetConfigurations: _makeRulesetConfigurations(configuration, address(dataHook), extraHookMetadata),
            terminalConfigurations: terminalConfigurations,
            memo: string.concat("$", symbol, " revnet deployed")
        });

        // Issue the network's ERC-20 token.
        CONTROLLER.deployERC20For({projectId: revnetId, name: name, symbol: symbol});

        // Setup the buyback hook.
        _setupBuybackHookOf(revnetId, buybackHookConfiguration);

        // Set the operator splits at the default ruleset of 0.
        CONTROLLER.setSplitGroupsOf({
            projectId: revnetId,
            rulesetId: 0,
            splitGroups: _makeOperatorSplitGroupWith(configuration.initialOperator)
        });

        // Premint tokens to the operator if needed.
        if (configuration.premintTokenAmount > 0) {
            CONTROLLER.mintTokensOf({
                projectId: revnetId,
                tokenCount: configuration.premintTokenAmount,
                beneficiary: configuration.initialOperator,
                memo: string.concat("$", symbol, " preminted"),
                useReservedRate: false
            });
        }

        // Deploy the suckers if needed.
        if (suckerDeploymentConfiguration.salt != bytes32(0)) {
            _deploySuckersOf({
                revnetId: revnetId,
                configuration: configuration,
                suckerDeploymentConfiguration: suckerDeploymentConfiguration
            });
        }

        // Give the operator permission to change the recipients of the operator's split.
        IJBPermissioned(address(CONTROLLER)).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: configuration.initialOperator,
                projectId: revnetId,
                permissionIds: _OPERATOR_PERMISSIONS_INDEXES
            })
        });
    }

    /// @notice Schedules the initial ruleset for the revnet, and queues all subsequent rulesets that define the stages.
    /// @notice configuration The data that defines the revnet's characteristics.
    /// @notice dataHook The address of the data hook.
    /// @notice extraMetadata Extra info to send to the hook.
    function _makeRulesetConfigurations(
        REVConfig memory configuration,
        address dataHook,
        uint256 extraMetadataData
    )
        internal
        pure
        virtual
        returns (JBRulesetConfig[] memory rulesetConfigurations)
    {
        // Keep a reference to the number of stages to schedule.
        uint256 numberOfStages = configuration.stageConfigurations.length;

        // Each stage is modeled as a ruleset reconfiguration.
        rulesetConfigurations = new JBRulesetConfig[](numberOfStages);

        // Loop through each stage to set up its ruleset configuration.
        for (uint256 i; i < numberOfStages; i++) {
            rulesetConfigurations[i].mustStartAtOrAfter = configuration.stageConfigurations[i].startsAtOrAfter;
            rulesetConfigurations[i].duration = configuration.stageConfigurations[i].priceCeilingIncreaseFrequency;
            // Set the initial issuance for the first ruleset, otherwise pass 0 to inherit from the previous
            // ruleset.
            rulesetConfigurations[i].weight = configuration.stageConfigurations[i].initialIssuanceRate;
            rulesetConfigurations[i].decayRate = configuration.stageConfigurations[i].priceCeilingIncreasePercentage;
            rulesetConfigurations[i].approvalHook = IJBRulesetApprovalHook(address(0));
            rulesetConfigurations[i].metadata = JBRulesetMetadata({
                reservedRate: configuration.stageConfigurations[i].operatorSplitRate,
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE
                    - configuration.stageConfigurations[i].priceFloorTaxIntensity,
                baseCurrency: configuration.baseCurrency,
                pausePay: false,
                pauseCreditTransfers: false,
                allowOwnerMinting: true, // Allow this contract to premint tokens as the network owner.
                allowTerminalMigration: false,
                allowSetTerminals: false,
                allowControllerMigration: false,
                allowSetController: false,
                holdFees: false,
                useTotalSurplusForRedemptions: false,
                useDataHookForPay: true, // Use the buyback hook data source.
                useDataHookForRedeem: false,
                dataHook: dataHook,
                metadata: extraMetadataData
            });
        }
    }

    /// @notice Creates a group of splits that goes entirely to the provided operator.

    /// @param operator The address to send the entire split amount to.
    /// @return splitGroups The split groups representing operator's split.
    function _makeOperatorSplitGroupWith(address operator) internal pure returns (JBSplitGroup[] memory splitGroups) {
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
            beneficiary: payable(operator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Set the item in the splits group.
        splitGroups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: splits});
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
    }

    /// @notice Stores pay hooks for the provided revnet.
    /// @param revnetId The ID of the revnet to which the pay hooks apply.
    /// @param payHookSpecifications The pay hooks to store.
    function _storeHookSpecificationsOf(
        uint256 revnetId,
        JBPayHookSpecification[] memory payHookSpecifications
    )
        internal
    {
        // Keep a reference to the number of pay hooks are being stored.
        uint256 numberOfPayHookSpecifications = payHookSpecifications.length;

        // Store the pay hooks.
        for (uint256 i; i < numberOfPayHookSpecifications; i++) {
            // Store the value.
            _payHookSpecificationsOf[revnetId].push(payHookSpecifications[i]);
        }
    }

    /// @notice Deploys suckers that allows a revnet to communicate across chains.
    /// @param revnetId The ID of the revnet to deploy the suckers for.
    /// @param suckerDeploymentConfiguration Information about how this revnet relates to other's across chains.
    function _deploySuckersOf(
        uint256 revnetId,
        REVConfig memory configuration,
        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration
    )
        internal
        virtual
    {
        // Keep a reference to the number of sucker deployers.
        uint256 numberOfSuckerDeployers = suckerDeploymentConfiguration.deployerConfigurations.length;

        // Keep a reference to the sucker deploy being iterated on.
        REVSuckerDeployerConfig memory deployerConfiguration;

        for (uint256 i; i < numberOfSuckerDeployers; i++) {
            //  Get the configuration being iterated on.
            deployerConfiguration = suckerDeploymentConfiguration.deployerConfigurations[i];

            // Create the sucker.
            IBPSucker sucker = deployerConfiguration.deployer.createForSender({
                _localProjectId: revnetId,
                _salt: keccak256(
                    abi.encodePacked(msg.sender, _encodeConfiguration(configuration), suckerDeploymentConfiguration.salt)
                    )
            });

            // Store the sucker.
            suckersOf[revnetId].push(sucker);

            // Keep a reference to the number of token configurations for the sucker.
            uint256 numberOfTokenConfigurations = deployerConfiguration.tokenConfigurations.length;

            // Keep a reference to the token configurations being iterated on.
            BPTokenConfig memory tokenConfiguration;

            // Configure the tokens for the sucker.
            for (uint256 j; j < numberOfTokenConfigurations; j++) {
                // Get a reference to the configuration being iterated on.
                tokenConfiguration = deployerConfiguration.tokenConfigurations[j];

                // Configure the sucker.
                sucker.configureToken(
                    BPTokenConfig({
                        localToken: tokenConfiguration.localToken,
                        remoteToken: tokenConfiguration.remoteToken,
                        minGas: tokenConfiguration.minGas,
                        minBridgeAmount: tokenConfiguration.minBridgeAmount
                    })
                );
            }
        }
    }

    function _encodeConfiguration(REVConfig memory configuration) internal pure returns (bytes memory encodedData) {
        encodedData = abi.encode(configuration.baseCurrency);

        uint256 numberOfStageConfigurations = configuration.stageConfigurations.length;
        REVStageConfig memory stageConfiguration;
        for (uint256 i; i < numberOfStageConfigurations; i++) {
            stageConfiguration = configuration.stageConfigurations[i];
            // Encode each child struct and append it
            encodedData = abi.encodePacked(
                encodedData,
                abi.encode(
                    stageConfiguration.startsAtOrAfter,
                    stageConfiguration.operatorSplitRate,
                    stageConfiguration.initialIssuanceRate,
                    stageConfiguration.priceCeilingIncreaseFrequency,
                    stageConfiguration.priceCeilingIncreasePercentage,
                    stageConfiguration.priceFloorTaxIntensity
                )
            );
        }
    }
}
