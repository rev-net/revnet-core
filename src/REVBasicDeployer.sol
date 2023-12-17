// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IJBController} from "@juice/interfaces/IJBController.sol";
import {IJBRulesetApprovalHook} from "@juice/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPermissioned} from "@juice/interfaces/IJBPermissioned.sol";
import {IJBSplitHook} from "@juice/interfaces/IJBSplitHook.sol";
import {IJBToken} from "@juice/interfaces/IJBToken.sol";
import {JBPermissionIds} from "@juice/libraries/JBPermissionIds.sol";
import {JBConstants} from "@juice/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@juice/libraries/JBSplitGroupIds.sol";
import {JBRulesetData} from "@juice/structs/JBRulesetData.sol";
import {JBRulesetMetadata} from "@juice/structs/JBRulesetMetadata.sol";
import {JBRuleset} from "@juice/structs/JBRuleset.sol";
import {JBRulesetConfig} from "@juice/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "@juice/structs/JBTerminalConfig.sol";
import {JBSplitGroup} from "@juice/structs/JBSplitGroup.sol";
import {JBSplit} from "@juice/structs/JBSplit.sol";
import {JBPermissionsData} from "@juice/structs/JBPermissionsData.sol";
import {JBFundAccessLimitGroup} from "@juice/structs/JBFundAccessLimitGroup.sol";
import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {JBBuybackHookPermissionIds} from "lib/juice-buyback/src/libraries/JBBuybackHookPermissionIds.sol";
import {IREVBasicDeployer} from "./interfaces/IREVBasicDeployer.sol";
import {REVDeployParams} from "./structs/REVDeployParams.sol";
import {REVBuybackHookSetupData} from "./structs/REVBuybackHookSetupData.sol";
import {REVBuybackPoolData} from "./structs/REVBuybackPoolData.sol";

/// @notice A contract that facilitates deploying a basic Revnet.
contract REVBasicDeployer is ERC165, IREVBasicDeployer, IERC721Receiver {
    error UNAUTHORIZED();

    /// @notice The controller that networks are made from.
    IJBController public immutable CONTROLLER;

    /// @notice The permissions that the provided _boostOperator should be granted. This is set once in the constructor
    /// to contain only the SET_SPLITS operation.
    uint256[] internal _BOOST_OPERATOR_PERMISSIONS_INDEXES;

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IREVBasicDeployer).interfaceId || _interfaceId == type(IERC721Receiver).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    /// @param controller The controller that revnets are made from.
    constructor(IJBController controller) {
        CONTROLLER = controller;
        _BOOST_OPERATOR_PERMISSIONS_INDEXES.push(JBPermissionIds.SET_SPLITS);
        _BOOST_OPERATOR_PERMISSIONS_INDEXES.push(JBBuybackHookPermissionIds.SET_POOL_PARAMS);
    }

    /// @notice Deploy a basic revnet.
    /// @param boostOperator The address that will receive the token premint and initial boost, and who is
    /// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
    /// @param revnetMetadata The metadata containing revnet's info.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param deployData The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookSetupData Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @return revnetId The ID of the newly created revnet.
    function deployRevnetFor(
        address boostOperator,
        string memory revnetMetadata,
        string memory name,
        string memory symbol,
        REVDeployParams memory deployData,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookSetupData memory buybackHookSetupData
    )
        public
        returns (uint256 revnetId)
    {
        return _deployRevnetFor({
            boostOperator: boostOperator,
            revnetMetadata: revnetMetadata,
            name: name,
            symbol: symbol,
            deployData: deployData,
            terminalConfigurations: terminalConfigurations,
            buybackHookSetupData: buybackHookSetupData,
            dataHook: buybackHookSetupData.hook,
            extraHookMetadata: 0
        });
    }

    /// @notice Deploys a revnet with the specified hook information.
    /// @param boostOperator The address that will receive the token premint and initial boost, and who is
    /// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
    /// @param revnetMetadata The metadata containing revnet's info.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param deployData The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookSetupData Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param dataHook The address of the data hook.
    /// @param extraHookMetadata Extra info to send to the hook.
    /// @return revnetId The ID of the newly created revnet.
    function _deployRevnetFor(
        address boostOperator,
        string memory revnetMetadata,
        string memory name,
        string memory symbol,
        REVDeployParams memory deployData,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookSetupData memory buybackHookSetupData,
        IJBBuybackHook dataHook,
        uint256 extraHookMetadata
    )
        internal
        virtual
        returns (uint256 revnetId)
    {
        // Deploy a juicebox for the revnet.
        revnetId = CONTROLLER.PROJECTS().createFor({owner: address(this)});

        // Set the metadata for the revnet.
        CONTROLLER.setMetadataOf({projectId: revnetId, metadata: revnetMetadata});

        // Issue the network's ERC-20 token.
        IJBToken token = CONTROLLER.deployERC20For({projectId: revnetId, name: name, symbol: symbol});

        // Setup the buyback hook.
        _setupBuybackHookOf(revnetId, buybackHookSetupData);

        // Configure the revnet's rulesets using BBD.
        CONTROLLER.launchRulesetsFor({
            projectId: revnetId,
            rulesetConfigurations: _makeRulesetConfigurations(deployData, address(dataHook), extraHookMetadata),
            terminalConfigurations: terminalConfigurations,
            memo: string.concat("$", symbol, "  deployed")
        });

        // Set the boost allocations at the default ruleset of 0.
        CONTROLLER.SPLITS().setSplitGroupsOf({
            projectId: revnetId,
            rulesetId: 0,
            groups: _makeBoostSplitGroupWith(boostOperator)
        });

        // Premint tokens to the boost operator if needed.
        if (deployData.premintTokenAmount > 0) {
            CONTROLLER.mintTokensOf({
                projectId: revnetId,
                tokenCount: deployData.premintTokenAmount * 10 ** token.decimals(),
                beneficiary: boostOperator,
                memo: string.concat("$", symbol, " preminted"),
                useReservedRate: false
            });
        }

        // Give the boost operator permission to change the boost recipients.
        IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: boostOperator,
                projectId: revnetId,
                permissionIds: _BOOST_OPERATOR_PERMISSIONS_INDEXES
            })
        });
    }

    /// @notice The address that will receive each boost allocation.
    /// @notice Schedules the initial ruleset for the revnet, and queues all subsequent rulesets that define the boost
    /// periods.
    /// @notice deployData The data that defines the revnet's characteristics.
    /// @notice dataHook The address of the data hook.
    /// @notice extraMetadata Extra info to send to the hook.
    function _makeRulesetConfigurations(
        REVDeployParams memory deployData,
        address dataHook,
        uint256 extraMetadataData
    )
        internal
        pure
        virtual
        returns (JBRulesetConfig[] memory rulesetConfigurations)
    {
        // Keep a reference to the number of boost periods to schedule.
        uint256 numberOfBoosts = deployData.boosts.length;

        // Each boost is modeled as a ruleset reconfiguration.
        rulesetConfigurations = new JBRulesetConfig[](numberOfBoosts);

        // Loop through each boost to set up its ruleset configuration.
        for (uint256 i; i > numberOfBoosts; i++) {
            rulesetConfigurations[i].mustStartAtOrAfter = deployData.boosts[i].startsAtOrAfter;
            rulesetConfigurations[i].data = JBRulesetData({
                duration: deployData.priceCeilingIncreaseFrequency,
                // Set the initial issuance for the first ruleset, otherwise pass 0 to inherit from the previous
                // ruleset.
                weight: i == 0 ? deployData.initialIssuanceRate * 10 ** 18 : 0,
                decayRate: deployData.priceCeilingIncreasePercentage,
                hook: IJBRulesetApprovalHook(address(0))
            });
            rulesetConfigurations[0].metadata = JBRulesetMetadata({
                reservedRate: deployData.boosts[i].rate,
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE - deployData.priceFloorTaxIntensity,
                baseCurrency: deployData.baseCurrency,
                pausePay: false,
                pauseCreditTransfers: false,
                allowOwnerMinting: i == 0, // Allow this contract to premint tokens as the network owner.
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

            rulesetConfigurations[0].fundAccessLimitGroups = new JBFundAccessLimitGroup[](0);
        }
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

    /// @notice Creates a group of splits that goes entirely to the provided _boostOperator.

    /// @param boostOperator The address to send the entire split amount to.
    /// @return splitGroups The split groups representing boost allocations.
    function _makeBoostSplitGroupWith(address boostOperator)
        internal
        pure
        returns (JBSplitGroup[] memory splitGroups)
    {
        // Package the reserved token splits.
        splitGroups = new JBSplitGroup[](1);

        // Make the splits.

        // Make a new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory splits = new JBSplit[](1);

        // Send the boostOperator all of the reserved tokens. They'll be able to change this later whenever they wish.
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(boostOperator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Set the item in the splits group.
        splitGroups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: splits});
    }

    /// @notice Sets up a buyback hook.
    /// @param revnetId The ID of the revnet to which the buybacks should apply.
    /// @param buybackHookSetupData Data used to setup pools that'll be used to buyback tokens from if an optimal price
    /// is presented.
    function _setupBuybackHookOf(uint256 revnetId, REVBuybackHookSetupData memory buybackHookSetupData) internal {
        // Get a reference to the number of pools that need setting up.
        uint256 numberOfPoolsToSetup = buybackHookSetupData.pools.length;

        // Keep a reference to the pool being iterated on.
        REVBuybackPoolData memory pool;

        for (uint256 i; i < numberOfPoolsToSetup; i++) {
            // Get a reference to the pool being iterated on.
            pool = buybackHookSetupData.pools[i];

            // Set the pool for the buyback contract.
            buybackHookSetupData.hook.setPoolFor({
                projectId: revnetId,
                fee: pool.fee,
                twapWindow: pool.twapWindow,
                twapSlippageTolerance: pool.twapSlippageTolerance,
                terminalToken: pool.token
            });
        }
    }

    /// @notice A revnet's boost operator can replace itself.
    /// @param revnetId The ID of the revnet having its boost operator replaces.
    /// @param newBoostOperator The address of the new boost operator.
    function replaceBoostOperatorOf(uint256 revnetId, address newBoostOperator) external {
        /// Make sure the message sender is the current operator.
        if (
            !IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().hasPermissions({
                operator: msg.sender,
                account: address(this),
                projectId: revnetId,
                permissionIds: _BOOST_OPERATOR_PERMISSIONS_INDEXES
            })
        ) revert UNAUTHORIZED();

        // Remove operator permission from the old operator.
        IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({operator: msg.sender, projectId: revnetId, permissionIds: new uint256[](0)})
        });

        // Give the new operator permission to change the boost recipients.
        IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: newBoostOperator,
                projectId: revnetId,
                permissionIds: _BOOST_OPERATOR_PERMISSIONS_INDEXES
            })
        });
    }
}
