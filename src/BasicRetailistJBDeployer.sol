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

/// @custom:member rate The percentage of newly issued tokens that should be reserved for the _operator. This
/// percentage is out of 10_000 (JBConstants.MAX_RESERVED_RATE).
/// @custom:member startsAtOrAfter The timestamp to start the dev tax at the given rate at or after.
struct DevTaxPeriod {
    uint128 rate;
    uint128 startsAtOrAfter;
}

/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 ETH contributed to the
/// treasury. This should _not_ be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _operator. This should _not_
/// be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member generationTax The rate at which the issuance rate should decrease over time. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_DISCOUNT_RATE).
/// 0% corresponds to no tax, everyone is treated equally over time.
/// @custom:member generationDuration The number of seconds between applied issuance reduction.
/// @custom:member exitTaxRate The bonding curve rate determining how much each token can access from the treasury at
/// any current total supply. This percentage is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE). 0% corresponds to no
/// tax (100% redemption rate).
/// @custom:member devTaxPeriods The periods of distinguished dev taxe rates that should be applied over time.
/// @custom:member poolFee The fee of the pool in which swaps occur when seeking the best price for a new participant.
/// This incentivizes liquidity providers. Out of 1_000_000. A common value is 1%, or 10_000. Other passible values are
/// 0.3% and 0.1%.
struct BasicRetailistJBParams {
    uint256 initialIssuanceRate;
    uint256 premintTokenAmount;
    uint256 generationTax;
    uint256 generationDuration;
    uint256 exitTaxRate;
    DevTaxPeriod[] devTaxPeriods;
    uint24 poolFee;
}

/// @notice A contract that facilitates deploying a basic Retailist network.
contract BasicRetailistJBDeployer is IERC721Receiver {
    error RECONFIGURATION_ALREADY_SCHEDULED();
    error RECONFIGURATION_NOT_POSSIBLE();
    error BAD_DEV_TAX_SEQUENCE();

    /// @notice The dev tax periods for each network.
    /// @dev A basic retailist treasury consists of funding cycles defined by scheduled dev taxes. The only changes
    /// between them are in their reserved rate.
    /// @custom:param _networkId The ID of the network to which the dev tax period applies.
    mapping(uint256 _networkId => DevTaxPeriod[]) internal _devTaxPeriodsOf;

    /// @notice The controller that networks are made from.
    IJBController3_1 public immutable controller;

    /// @notice The permissions that the provided _operator should be granted. This is set once in the constructor to
    /// contain only the SET_SPLITS operation.
    uint256[] public operatorPermissionIndexes;

    /// @notice The current index of dev tax period that each network is in, relative to devTaxPeriodsOf.
    /// @custom:param _networkId The ID of the network to which the dev tax period applies.
    mapping(uint256 _networkId => uint256) public currentDevTaxPeriodNumberOf;

    /// @notice The dev tax periods for each network.
    /// @dev A basic retailist treasury consists of funding cycles defined by scheduled dev taxes. The only changes
    /// between them are in their reserved rate.
    /// @custom:param _networkId The ID of the network to which the dev tax period applies.
    function devTaxPeriodsOf(uint256 _networkId) external view returns (DevTaxPeriod[] memory) {
        return _devTaxPeriodsOf[_networkId];
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IERC721Receiver).interfaceId;
    }

    /// @param _controller The controller that networks are made from.
    constructor(IJBController3_1 _controller) {
        controller = _controller;
        operatorPermissionIndexes.push(JBOperations.SET_SPLITS);
        operatorPermissionIndexes.push(JBBuybackDelegateOperations.SET_POOL_PARAMS);
    }

    /// @notice Deploy a network with basic Retailism constraints.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is
    /// allowed to change the allocated reserved rate distribution.
    /// @param _networkMetadata The metadata containing network info.
    /// @param _name The name of the ERC-20 token being create for the network.
    /// @param _symbol The symbol of the ERC-20 token being created for the network.
    /// @param _data The data needed to deploy a basic retailist network.
    /// @param _terminals The terminals that the network uses to accept payments through.
    /// @param _buybackDelegate The buyback delegate to use when determining the best price for new participants.
    /// @return networkId The ID of the newly created Retailist network.
    function deployBasicNetworkFor(
        address _operator,
        JBProjectMetadata memory _networkMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams memory _data,
        IJBPaymentTerminal[] memory _terminals,
        IJBGenericBuybackDelegate _buybackDelegate
    )
        public
        returns (uint256 networkId)
    {
        // Make the dev tax allocation.
        JBGroupedSplits[] memory _groupedSplits = _makeDevTaxSplitGroupWith(_operator);

        // Deploy a network.
        networkId = controller.projects().createFor({
            owner: address(this), // This contract should remain the owner, forever.
            metadata: _networkMetadata
        });

        // Issue the network's ERC-20 token.
        controller.tokenStore().issueFor({ projectId: networkId, name: _name, symbol: _symbol });

        // Set the pool for the buyback delegate.
        _buybackDelegate.setPoolFor({
            _projectId: networkId,
            _fee: _data.poolFee,
            _secondsAgo: uint32(_buybackDelegate.MIN_SECONDS_AGO()),
            _twapDelta: uint32(_buybackDelegate.MAX_TWAP_DELTA()),
            _terminalToken: JBTokens.ETH
        });

        // Configure the network's funding cycles using BBD.
        controller.launchFundingCyclesFor({
            projectId: networkId,
            data: JBFundingCycleData({
                duration: _data.generationDuration,
                weight: _data.initialIssuanceRate ** 18,
                discountRate: _data.generationTax,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            metadata: JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: _data.devTaxPeriods.length == 0 ? 0 : _data.devTaxPeriods[0].rate, // Set the reserved rate.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE - _data.exitTaxRate, // Set the redemption rate.
                ballotRedemptionRate: 0, // There will never be an active ballot, so this can be left off.
                pausePay: false,
                pauseDistributions: false, // There will never be distributions accessible anyways.
                pauseRedeem: false, // Redemptions must be left open.
                pauseBurn: false,
                allowMinting: true, // Allow this contract to premint tokens as the network owner.
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true, // Use the buyback delegate data source.
                useDataSourceForRedeem: false,
                dataSource: address(_buybackDelegate),
                metadata: 0
            }),
            mustStartAtOrAfter: _data.devTaxPeriods.length == 0 ? 0 : _data.devTaxPeriods[0].startsAtOrAfter,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: new JBFundAccessConstraints[](0), // Funds can't be accessed by the network owner.
            terminals: _terminals,
            memo: "Deployed Retailist network"
        });

        // Premint tokens to the Operator.
        controller.mintTokensOf({
            projectId: networkId,
            tokenCount: _data.premintTokenAmount ** 18,
            beneficiary: _operator,
            memo: string.concat("Preminted $", _symbol),
            preferClaimedTokens: false,
            useReservedRate: false
        });

        // Give the operator permission to change the allocated reserved rate distribution destination.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({ operator: _operator, domain: networkId, permissionIndexes: operatorPermissionIndexes })
        );

        // Store the dev tax periods so they can be queued via calls to `scheduleNextDevTaxPeriodOf(...)`.
        _storeDevTaxPeriodsOf(networkId, _data.devTaxPeriods, _data.generationDuration);
    }

    /// @notice Schedules the new dev tax period that adjusts the reserved rate based on the
    /// dev tax periods passed when the network was deployed.
    /// @param _networkId The ID of the network who is having its dev tax periods scheduled.
    function scheduleNextDevTaxPeriodOf(uint256 _networkId) external {
        // Get a reference to the latest configured funding cycle and its metadata.
        (JBFundingCycle memory _latestFundingCycleConfiguration, JBFundingCycleMetadata memory _metadata,) =
            controller.latestConfiguredFundingCycleOf(_networkId);

        // Get a reference to the next dev tax period number, while incrementing the stored value. Zero indexed.
        uint256 _nextDevTaxPeriodNumber = ++currentDevTaxPeriodNumberOf[_networkId];

        // Get a reference to the number of dev tax periods there are. One indexed.
        uint256 _numberOfDevTaxPeriods = _devTaxPeriodsOf[_networkId].length;

        // Make sure the latest funding cycle configured started in the past, and that there are more dev tax periods to
        // schedule.
        if (
            _numberOfDevTaxPeriods == 0 || _nextDevTaxPeriodNumber == _numberOfDevTaxPeriods
                || _latestFundingCycleConfiguration.start > block.timestamp
        ) revert RECONFIGURATION_ALREADY_SCHEDULED();

        // Get a reference to the next dev tax period.
        DevTaxPeriod memory _devTax = _devTaxPeriodsOf[_networkId][_nextDevTaxPeriodNumber];

        // Schedule a funding cycle reconfiguration.
        controller.reconfigureFundingCyclesOf({
            projectId: _networkId,
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
                reservedRate: _devTax.rate, // Set the reserved rate.
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
            mustStartAtOrAfter: _devTax.startsAtOrAfter,
            groupedSplits: _copyDevTaxSplitGroupFrom(_networkId, _latestFundingCycleConfiguration.configuration),
            fundAccessConstraints: new JBFundAccessConstraints[](0),
            memo: "Scheduled next dev tax period of Retailist network"
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

    /// @notice Creates a group of splits that goes entirely to the provided operator address.
    /// @param _operator The address to send the entire split amount to.
    /// @return _groupedSplits The grouped splits to be used in a configuration.
    function _makeDevTaxSplitGroupWith(address _operator)
        internal
        pure
        returns (JBGroupedSplits[] memory _groupedSplits)
    {
        // Package the reserved token splits.
        _groupedSplits = new JBGroupedSplits[](1);

        // Make the splits.

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

    /// @notice Copies a group of splits from  the one stored in the provided configuration.
    /// @param _networkId The network to which the splits apply.
    /// @param _baseConfiguration The configuration to copy configurations from.
    /// @return _groupedSplits The grouped splits to be used in a configuration.
    function _copyDevTaxSplitGroupFrom(
        uint256 _networkId,
        uint256 _baseConfiguration
    )
        internal
        view
        returns (JBGroupedSplits[] memory _groupedSplits)
    {
        // Package the reserved token splits.
        _groupedSplits = new JBGroupedSplits[](1);

        // Make a new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory _splits =
            controller.splitsStore().splitsOf(_networkId, _baseConfiguration, JBSplitsGroups.RESERVED_TOKENS);

        _groupedSplits[0] = JBGroupedSplits({ group: JBSplitsGroups.RESERVED_TOKENS, splits: _splits });
    }

    /// @notice Stores dev tax periods after checking if they were provided in an acceptable order.
    /// @param _networkId The ID to which the dev taxes apply.
    /// @param _devTaxPeriods The dev tax periods to store.
    /// @param _generationDuration The generation duration to expect each dev tax period to be at least as long.
    function _storeDevTaxPeriodsOf(
        uint256 _networkId,
        DevTaxPeriod[] memory _devTaxPeriods,
        uint256 _generationDuration
    )
        internal
    {
        // Keep a reference to the number of dev tax periods.
        uint256 _numberOfDevTaxPeriods = _devTaxPeriods.length;

        // Store the dev tax periods. Separate transactions to
        // `scheduleNextDevTaxPeriodOf` must be called to formally scheduled them.
        if (_numberOfDevTaxPeriods != 0) {
            for (uint256 _i; _i < _numberOfDevTaxPeriods;) {
                // Make sure the dev taxes have incrementally positive start times, and are each at least one generation
                // long.
                if (
                    _i != 0
                        && _devTaxPeriods[_i].startsAtOrAfter
                            <= _devTaxPeriods[_i - 1].startsAtOrAfter + _generationDuration
                ) revert BAD_DEV_TAX_SEQUENCE();

                // Store the dev tax period.
                _devTaxPeriodsOf[_networkId][_i] = _devTaxPeriods[_i];
                unchecked {
                    ++_i;
                }
            }
        }
    }
}
