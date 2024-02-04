// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBRulesetApprovalHook} from "lib/juice-contracts-v4/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPermissioned} from "lib/juice-contracts-v4/src/interfaces/IJBPermissioned.sol";
import {IJBSplitHook} from "lib/juice-contracts-v4/src/interfaces/IJBSplitHook.sol";
import {IJBToken} from "lib/juice-contracts-v4/src/interfaces/IJBToken.sol";
import {JBPermissionIds} from "lib/juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {JBConstants} from "lib/juice-contracts-v4/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "lib/juice-contracts-v4/src/libraries/JBSplitGroupIds.sol";
import {JBRulesetMetadata} from "lib/juice-contracts-v4/src/structs/JBRulesetMetadata.sol";
import {JBRulesetConfig} from "lib/juice-contracts-v4/src/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {JBSplitGroup} from "lib/juice-contracts-v4/src/structs/JBSplitGroup.sol";
import {JBSplit} from "lib/juice-contracts-v4/src/structs/JBSplit.sol";
import {JBPermissionsData} from "lib/juice-contracts-v4/src/structs/JBPermissionsData.sol";
import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {JBBuybackPermissionIds} from "lib/juice-buyback/src/libraries/JBBuybackPermissionIds.sol";

import {IREVBasicDeployer} from "./interfaces/IREVBasicDeployer.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "./structs/REVBuybackPoolConfig.sol";

/// @notice A contract that facilitates deploying a basic Revnet.
contract REVBasicDeployer is ERC165, IREVBasicDeployer, IERC721Receiver {
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
    // ------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice The permissions that the provided operator should be granted. This is set once in the constructor
    /// to contain only the SET_SPLITS operation.
    /// @dev This should only be set in the constructor.
    uint256[] internal _OPERATOR_PERMISSIONS_INDEXES;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

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
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IREVBasicDeployer).interfaceId || _interfaceId == type(IERC721Receiver).interfaceId
            || super.supportsInterface(_interfaceId);
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
    /// @param projectMetadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @return revnetId The ID of the newly created revnet.
    function deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory projectMetadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration
    )
        public
        override
        returns (uint256 revnetId)
    {
        return _deployRevnetWith({
            name: name,
            symbol: symbol,
            projectMetadata: projectMetadata,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: buybackHookConfiguration.hook,
            extraHookMetadata: 0
        });
    }

    //*********************************************************************//
    // --------------------- itnernal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Deploys a revnet with the specified hook information.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param projectMetadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param dataHook The address of the data hook.
    /// @param extraHookMetadata Extra info to send to the hook.
    /// @return revnetId The ID of the newly created revnet.
    function _deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory projectMetadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        IJBBuybackHook dataHook,
        uint256 extraHookMetadata
    )
        internal
        virtual
        returns (uint256 revnetId)
    {
        // Deploy a juicebox for the revnet.
        revnetId = CONTROLLER.launchProjectFor({
            owner: address(this),
            projectMetadata: projectMetadata,
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
    function _makeOperatorSplitGroupWith(address operator)
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
}
