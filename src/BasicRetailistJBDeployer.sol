// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBController3_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import { IJBPayoutRedemptionPaymentTerminal3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import { IJBFundingCycleBallot } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import { IJBOperatable } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import { IJBSplitAllocator } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import { IJBToken } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol";
import { JBOperations } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import { JBConstants } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import { JBTokens } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import { JBSplitsGroups } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol";
import { JBFundingCycleData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import { JBFundingCycleMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import { JBFundingCycle } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import { JBGlobalFundingCycleMetadata } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import { JBGroupedSplits } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import { JBSplit } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import { JBOperatorData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import { JBFundAccessConstraints } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import { JBProjectMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import { IJBGenericBuybackDelegate } from
    "@jbx-protocol/juice-buyback-delegate/contracts/interfaces/IJBGenericBuybackDelegate.sol";
import { JBBuybackDelegateOperations } from
    "@jbx-protocol/juice-buyback-delegate/contracts/libraries/JBBuybackDelegateOperations.sol";

/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 ETH contributed to the
/// treasury. This should _not_ be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _operator. This should _not_
/// be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member discountRate The rate at which the issuance rate should decrease over time.
/// @custom:member cycleDurations The number of seconds between applied discounts.
/// @custom:member redemptionRate The bonding curve rate determining how much each token can access from the treasury at
/// any current total supply. This percentage is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE).
/// @custom:member reservedRate The percentage of newly issued tokens that should be reserved for the _operator. This
/// percentage is out of 10_000 (JBConstants.MAX_RESERVED_RATE).
/// @custom:member reservedRateDuration The number of seconds the reserved rate should be active for.
struct BasicRetailistJBParams {
    uint256 initialIssuanceRate;
    uint256 premintTokenAmount;
    uint256 discountRate;
    uint256 cycleDurations;
    uint256 redemptionRate;
    uint256 reservedRate;
    uint48 reservedRateDuration;
}

/// @notice A contract that facilitates deploying a basic Retailist treasury.
contract BasicRetailistJBDeployer is IERC721Receiver {
    error RECONFIGURATION_ALREADY_SCHEDULED();

    /// @notice The controller that projects are made from.
    IJBController3_1 public immutable controller;

    /// @notice The buyback delegate.
    IJBGenericBuybackDelegate public immutable buybackDelegate;

    /// @notice The terminals that projects use to accept payments from. This is set once in the constructor to be the
    /// 3.1.1 payment terminal.
    IJBPaymentTerminal[] public terminals;

    /// @notice The permissions that the provided _operator should be granted. This is set once in the constructor to
    /// contain only the SET_SPLITS operation.
    uint256[] public permissionIndexes;

    /// @notice The start time of the reconfigurations for each project.
    /// @dev A basic retailist treasury consists of two funding cycles, one created on launch with a reserved rate, and
    /// another that starts at some point in the future that removes the reserved rate.
    /// @custom:param projectId The ID of the project to which the reconfiguration start time applies.
    mapping(uint256 projectId => uint256) public reconfigurationStartTimestampOf;

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IERC721Receiver).interfaceId;
    }

    /// @param _controller The controller that projects are made from.
    /// @param _terminal The terminal that projects use to accept payments from.
    /// @param _buybackDelegate The buyback delegate to use.
    constructor(
        IJBController3_1 _controller,
        IJBPayoutRedemptionPaymentTerminal3_1_1 _terminal,
        IJBGenericBuybackDelegate _buybackDelegate
    ) {
        controller = _controller;
        buybackDelegate = _buybackDelegate;
        terminals.push(_terminal);

        permissionIndexes.push(JBOperations.SET_SPLITS);
        permissionIndexes.push(JBBuybackDelegateOperations.SET_POOL_PARAMS);
    }

    /// @notice Deploy a project with basic Retailism constraints.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is
    /// allowed to change the allocated reserved rate distribution.
    /// @param _projectMetadata The metadata containing project info.
    /// @param _name The name of the ERC-20 token being create for the project.
    /// @param _symbol The symbol of the ERC-20 token being created for the project.
    /// @param _data The data needed to deploy a basic retailist project.
    /// @return projectId The ID of the newly created Retailist project.
    function deployBasicProjectFor(
        address _operator,
        JBProjectMetadata calldata _projectMetadata,
        string calldata _name,
        string calldata _symbol,
        BasicRetailistJBParams calldata _data
    )
        public
        returns (uint256 projectId)
    {
        // Package the reserved token splits.
        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);

        // Make the splits.
        {
            // Make a new splits specifying where the reserved tokens will be sent.
            JBSplit[] memory _splits = new JBSplit[](1);

            // Send the _operator all of the reserved tokens. They'll be able to change this later whenever they wish.
            _splits[1] = JBSplit({
                preferClaimed: false,
                preferAddToBalance: false,
                percent: JBConstants.SPLITS_TOTAL_PERCENT,
                projectId: 0,
                beneficiary: payable(_operator),
                lockedUntil: 0,
                allocator: IJBSplitAllocator(address(0))
            });

            _groupedSplits[0] = JBGroupedSplits({ group: JBSplitsGroups.RESERVED_TOKENS, splits: _splits });
        }

        // Deploy a project.
        projectId = controller.projects().createFor({
            owner: address(this), // This contract should remain the owner, forever.
            metadata: _projectMetadata
        });

        // Issue the project's ERC-20 token.
        controller.tokenStore().issueFor({ projectId: projectId, name: _name, symbol: _symbol });

        // Set the pool for the buyback delegate.
        buybackDelegate.setPoolFor({
            _projectId: projectId,
            _fee: 1,
            _secondsAgo: uint32(buybackDelegate.MIN_SECONDS_AGO()),
            _twapDelta: uint32(buybackDelegate.MAX_TWAP_DELTA()),
            _terminalToken: JBTokens.ETH
        });

        // Configure the project's funding cycles using BBD.
        controller.launchFundingCyclesFor({
            projectId: projectId,
            data: JBFundingCycleData({
                duration: _data.cycleDurations,
                weight: _data.initialIssuanceRate ** 18,
                discountRate: _data.discountRate,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            metadata: JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: _data.reservedRate, // Set the reserved rate.
                redemptionRate: _data.redemptionRate, // Set the redemption rate.
                ballotRedemptionRate: 0, // There will never be an active ballot, so this can be left off.
                pausePay: false,
                pauseDistributions: false, // There will never be distributions accessible anyways.
                pauseRedeem: false, // Redemptions must be left open.
                pauseBurn: false,
                allowMinting: true, // Allow this contract to premint tokens as the project owner.
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true, // Use the buyback delegate data source.
                useDataSourceForRedeem: false,
                dataSource: address(buybackDelegate),
                metadata: 0
            }),
            mustStartAtOrAfter: 0,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: new JBFundAccessConstraints[](0), // Funds can't be accessed by the project owner.
            terminals: terminals,
            memo: "Deployed Retailist treasury"
        });

        // Premint tokens to the Operator.
        controller.mintTokensOf({
            projectId: projectId,
            tokenCount: _data.premintTokenAmount ** 18,
            beneficiary: _operator,
            memo: string.concat("Preminted ", _symbol, " tokens."),
            preferClaimedTokens: false,
            useReservedRate: false
        });

        // Give the operator permission to change the allocated reserved rate distribution destination.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({ operator: _operator, domain: projectId, permissionIndexes: permissionIndexes })
        );

        // Store the timestamp after which the project's reconfigurd funding cycles can start. A separate transaction to
        // `scheduledReconfigurationOf` must be called to formally scheduled it.
        reconfigurationStartTimestampOf[projectId] = block.timestamp + _data.reservedRateDuration;
    }

    /// @notice Schedules the funding cycle reconfiguration that removes the reserved rate based on the
    /// _reservedRateDuration timestamp passed when the project was deployed.
    /// @param _projectId The ID of the project who is having its funding cycle reconfigation scheduled.
    function scheduleReconfigurationOf(uint256 _projectId) external {
        // Get a reference to the latest configured funding cycle and its metadata.
        (JBFundingCycle memory _latestFundingCycleConfiguration, JBFundingCycleMetadata memory _metadata,) =
            controller.latestConfiguredFundingCycleOf(_projectId);

        // Make sure the latest funding cycle scheduled was the first funding cycle.
        if (_latestFundingCycleConfiguration.number != 1) revert RECONFIGURATION_ALREADY_SCHEDULED();

        // Schedule a funding cycle reconfiguration.
        controller.reconfigureFundingCyclesOf({
            projectId: _projectId,
            data: JBFundingCycleData({
                duration: _latestFundingCycleConfiguration.duration,
                weight: 0, // Inherit the weight of the current funding cycle.
                discountRate: _latestFundingCycleConfiguration.discountRate,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            metadata: JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: 0, // No more reserved rate.
                redemptionRate: _metadata.redemptionRate, // Set the same redemption rate.
                ballotRedemptionRate: 0, // There will never be an active ballot, so this can be left off.
                pausePay: false,
                pauseDistributions: false,
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: false,
                useDataSourceForRedeem: false,
                dataSource: _metadata.dataSource,
                metadata: _metadata.metadata
            }),
            mustStartAtOrAfter: reconfigurationStartTimestampOf[_projectId],
            groupedSplits: new JBGroupedSplits[](0), // No more splits.
            fundAccessConstraints: new JBFundAccessConstraints[](0),
            memo: "Scheduled boost expiry of Retailist treasury"
        });
    }

    /// @dev Make sure only mints can be received.
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    )
        external
        view
        returns (bytes4)
    {
        _data;
        _tokenId;
        _operator;

        // Make sure the 721 received is the JBProjects contract.
        if (msg.sender != address(controller.projects())) revert();
        // Make sure the 721 is being received as a mint.
        if (_from != address(0)) revert();
        return IERC721Receiver.onERC721Received.selector;
    }
}
