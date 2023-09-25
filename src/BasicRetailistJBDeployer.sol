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

/// @custom:member rate The percentage of newly issued tokens that should be reserved for the _boostOperator, out of 10_000 (JBConstants.MAX_RESERVED_RATE).
/// @custom:member startsAtOrAfter The timestamp to start a boost at the given rate at or after.
struct Boost {
    uint128 rate;
    uint128 startsAtOrAfter;
}

/// @custom:member token The token to setup a pool for.
/// @custom:member poolFee The fee of the pool in which swaps occur when seeking the best price for a new participant.
/// This incentivizes liquidity providers. Out of 1_000_000. A common value is 1%, or 10_000. Other passible values are
/// 0.3% and 0.1%.
/// @custom:member twapWindow The time window to take into account when quoting a price based on TWAP.
/// @custom:member twapSlippageTolerance The pricetolerance to accept when quoting a price based on TWAP.
struct BuybackPool {
    address token;
    uint24 fee;
    uint32 twapWindow;
    uint32 twapSlippageTolerance;
}

/// @custom:member contract The buyback contract contract to use.
/// @custom:member pools The pools to setup on the given buyback contract.
struct BuybackSetup {
    IJBGenericBuybackDelegate contract;
    BuybackDelegatePool[] pools;
}

/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 currency unit contributed to the
/// revnet. This should _not_ be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _boostOperator. This should _not_
/// be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member generationDuration The number of seconds between applied issuance reductions. This should be at least 24 hours.
/// @custom:member priceCeilingIncreaseRate The rate at which the issuance rate should decrease over time, which in turn increases the price ceiling. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_DISCOUNT_RATE). 0% corresponds to no issuance reduction, everyone is treated equally over time.
/// @custom:member priceFloorIncreaseRate The rate determining how much each token can access from the revnet any current total supply by burning tokens. 
/// This percentage is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE). 0% corresponds to no floor increases when redemptions are made (100% redemption rate), everyone's redemptions are treated equally.
/// @custom:member boosts The periods of distinguished boosting that should be applied over time.
struct RevnetParams {
    uint256 initialIssuanceRate;
    uint256 premintTokenAmount;
    uint256 generationDuration;
    uint256 priceCeilingIncreaseRate;
    uint256 priceFloorInreaseRate;
    Boost[] boosts;
}

/// @notice A contract that facilitates deploying a basic Revnet.
contract BasicRevnetDeployer is IERC721Receiver {
    error RECONFIGURATION_ALREADY_SCHEDULED();
    error RECONFIGURATION_NOT_POSSIBLE();
    error BAD_BOOST_SEQUENCE();
    error UNAUTHORIZED();

    /// @notice The boosts for each network.
    /// @dev A basic revnet consists of cycles defined by scheduled boosts. The only changes between them are in their reserved rate.
    /// @custom:param _revnetId The ID of the revnet to which the boosts apply.
    mapping(uint256 _revnetId => Boost[]) internal _boostsOf;

    /// @notice The controller that networks are made from.
    IJBController3_1 public immutable controller;

    /// @notice The permissions that the provided _boostOperator should be granted. This is set once in the constructor to contain only the SET_SPLITS operation.
    uint256[] public boostOperatorPermissionIndexes;

    /// @notice The current index of the boost that each revnet is in, relative to _boostsOf.
    /// @custom:param _revnetId The ID of the revnet to which the boost applies.
    mapping(uint256 _revnetId => uint256) public currentBoostNumberOf;

    /// @notice The boosts for each network.
    /// @dev A basic revnet consists of cycles defined by scheduled boost periods. The only changes between them are in their reserved rate.
    /// @custom:param _revnetId The ID of the revnet to which the boost period applies.
    function boostsOf(uint256 _revnetId) external view returns (Boost[] memory) {
        return _boostsOf[_revnetId];
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
        boostOperatorPermissionIndexes.push(JBOperations.SET_SPLITS);
        boostOperatorPermissionIndexes.push(JBBuybackDelegateOperations.SET_POOL_PARAMS);
    }

    /// @notice Deploy a basic revnet.
    /// @param _boostOperator The address that will receive the token premint and initial boost, and who is
    /// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
    /// @param _revnetMetadata The metadata containing revnet's info.
    /// @param _name The name of the ERC-20 token being create for the revnet.
    /// @param _symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param _revnetData The data needed to deploy a basic revnet.
    /// @param _terminals The terminals that the network uses to accept payments through.
    /// @param _buybackSetup Info for setting up the buyback contract to use when determining the best price for new participants.
    /// @return revnetId The ID of the newly created revnet.
    function deployRevnetFor(
        address _boostOperator,
        JBProjectMetadata memory _revnetMetadata,
        string memory _name,
        string memory _symbol,
        RevnetParams memory _revnetData,
        IJBPaymentTerminal[] memory _terminals,
        BuybackSetup memory _buybackSetup
    )
        public
        returns (uint256 revnetId)
    {
        // Make the boost allocation.
        JBGroupedSplits[] memory _groupedSplits = _makeBoostSplitGroupWith(_boostOperator);

        // Deploy a juicebox for the revnet.
        revnetId = controller.projects().createFor({
            owner: address(this), // This contract should remain the owner, forever.
            metadata: _revnetMetadata
        });

        // Issue the network's ERC-20 token.
        controller.tokenStore().issueFor({ projectId: revnetId, name: _name, symbol: _symbol });
        
        // Setup the buyback delegate.
        _setupBuybackOf(revnetId, _buybackSetup);

        // Configure the revnet's cycles using BBD.
        controller.launchFundingCyclesFor({
            projectId: networkId,
            data: JBFundingCycleData({
                duration: _revnetData.generationDuration,
                weight: _revnetData.initialIssuanceRate * 10 ** 18,
                discountRate: _data.priceCeilingIncreaseRate,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            metadata: JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: _revnetData.boosts.length == 0 ? 0 : _revnetData.boosts[0].rate, // Set the reserved rate that'll model the boost periods.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE - _data.priceFloorIncreaseRate, // Set the redemption rate.
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
                dataSource: address(_buybackSetup.contract),
                metadata: 0
            }),
            mustStartAtOrAfter: _data.boosts.length == 0 ? 0 : _data.boosts[0].startsAtOrAfter,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: new JBFundAccessConstraints[](0), // Funds can't be accessed by the network owner.
            terminals: _terminals,
            memo: "revnet deployed"
        });

        // Premint tokens to the Boost Operator.
        controller.mintTokensOf({
            projectId: revnetId,
            tokenCount: _data.premintTokenAmount * 10 ** 18,
            beneficiary: _boostOperator,
            memo: string.concat("$", _symbol, " preminted"),
            preferClaimedTokens: false,
            useReservedRate: false
        });

        // Give the operator permission to change the boost recipients.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({ operator: _boostOperator, domain: revnetId, permissionIndexes: boostOperatorPermissionIndexes })
        );

        // Store the boost periods so they can be queued via calls to `scheduleNextBoostPeriodOf(...)`.
        _storeBoostPeriodsOf(networkId, _revnetData.boosts, _revnetData.generationDuration);
    }

    /// @notice Schedules the next boost specified when the revnet was deployed.
    /// @param _revnetId The ID of the revnet having its next boost scheduled.
    function scheduleNextBoostOf(uint256 _revnetId) external {
        // Get a reference to the latest configured cycle and its metadata.
        (JBFundingCycle memory _latestFundingCycleConfiguration, JBFundingCycleMetadata memory _metadata,) =
            controller.latestConfiguredFundingCycleOf(_revnetId);

        // Get a reference to the next boost number, while incrementing the stored value. Zero indexed.
        uint256 _nexBoostNumber = ++currentBoostNumberOf[_revnetId];

        // Get a reference to the number of boosts there are. 1 indexed.
        uint256 _numberOfBoosts = _boostOf[_revnetId].length;

        // Make sure the latest cycle configured started in the past, and that there are more boosts to schedule.
        if (
            _numberOfBoosts == 0 || _nextBoostNumber == _numberOfBoosts
                || _latestFundingCycleConfiguration.start >= block.timestamp
        ) revert RECONFIGURATION_ALREADY_SCHEDULED();

        // Get a reference to the next boost.
        Boost memory _boost = _boostsOf[_revnetId][_nextBoostNumber];

        // Schedule a cycle reconfiguration.
        controller.reconfigureFundingCyclesOf({
            projectId: _revnetId,
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
                reservedRate: _boost.rate, // Set the reserved rate to model the boost.
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
            mustStartAtOrAfter: _boost.startsAtOrAfter,
            groupedSplits: _copyDevTaxSplitGroupFrom(_revnetId, _latestFundingCycleConfiguration.configuration),
            fundAccessConstraints: new JBFundAccessConstraints[](0),
            memo: "revnet boost scheduled"
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

    /// @notice Creates a group of splits that goes entirely to the provided _boostOperator.
    /// @param _boostOperator The address to send the entire split amount to.
    /// @return _groupedSplits The grouped splits to be used in a configuration.
    function _makeBoostSplitGroupWith(address _boostOperator)
        internal
        pure
        returns (JBGroupedSplits[] memory _groupedSplits)
    {
        // Package the reserved token splits.
        _groupedSplits = new JBGroupedSplits[](1);

        // Make the splits.

        // Make a new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory _splits = new JBSplit[](1);

        // Send the _boostOperator all of the reserved tokens. They'll be able to change this later whenever they wish.
        _splits[1] = JBSplit({
            preferClaimed: false,
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(_boostOperator),
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        _groupedSplits[0] = JBGroupedSplits({ group: JBSplitsGroups.RESERVED_TOKENS, splits: _splits });
    }

    /// @notice Copies a group of splits from  the one stored in the provided configuration.
    /// @param _networkId The network to which the splits apply.
    /// @param _baseConfiguration The configuration to copy configurations from.
    /// @return _groupedSplits The grouped splits to be used in a configuration.
    function _copyBoostSplitGroupFrom(
        uint256 _revnetId,
        uint256 _baseConfiguration
    )
        internal
        view
        returns (JBGroupedSplits[] memory _groupedSplits)
    {
        // Package the reserved token splits.
        _groupedSplits = new JBGroupedSplits[](1);

        // Make new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory _splits =
            controller.splitsStore().splitsOf(_revnetId, _baseConfiguration, JBSplitsGroups.RESERVED_TOKENS);

        _groupedSplits[0] = JBGroupedSplits({ group: JBSplitsGroups.RESERVED_TOKENS, splits: _splits });
    }

    /// @notice Sets up buyback pools.
    /// @param _revnetId The ID of the revnet to which the buybacks should apply.
    /// @param _buybackSetup Info to setup pools that'll be used to buyback tokens from if an optimal price is presented.
    function _setupBuybackOf(uint256 _revnetId, BuybackSetup memory _buybackSetup) internal {

        // Get a reference to the number of pools that need setting up.
        uint256 _numberOfPoolsToSetup = _buybackSetup.pools.length;

        // Keep a reference to the pool being iterated on.
        BuybackPool memory _pool;

        for (uint256 _i; _i < _numberOfPoolsToSetup;) {
            // Get a reference to the pool being iterated on.
            _pool = _buybackSetup.pools[_i];

            // Set the pool for the buyback contract.
            _buybackSetup.contract.setPoolFor({
                _projectId: _revnetId,
                _fee: _pool.fee,
                _secondsAgo: _pool.twapWindow,
                _twapDelta: _pool.twapSlippageTolerance,
                _terminalToken: _pool.token
            });

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Stores boosts after checking if they were provided in an acceptable order.
    /// @param _revnetId The ID of the revnet to which the boosts apply.
    /// @param _boosts The boosts to store.
    /// @param _generationDuration The generation duration to expect each boost to be at least as long.
    function _storeBoostsOf(
        uint256 _revnetId,
        Boost[] memory _boosts,
        uint256 _generationDuration
    )
        internal
    {
        // Keep a reference to the number of boosts.
        uint256 _numberOfBoosts = _boosts.length;

        // Keep a reference to the boost being iterated on.
        Boost memory _boost;

        // Store the boost. Separate transactions to `scheduleNextBoostPeriodOf` must be called to schedule each of them.
        if (_numberOfBoosts != 0) {
            for (uint256 _i; _i < _numberOfBoosts;) {

                // Set the boost being iterated on.
                _boost = _boosts[_i];

                // Make sure the boosts have incrementally positive start times, and are each at least one generation long.
                if (
                    _i != 0
                        && _boost.startsAtOrAfter
                            <= _boosts[_i - 1].startsAtOrAfter + _generationDuration
                ) revert BAD_BOOST_SEQUENCE();

                // Store the boost.
                _boostsOf[_revnetId][_i] = _boost;
                unchecked {
                    ++_i;
                }
            }
        }
    }

    /// @notice A revnet's boost operator can replace itself.
    /// @param _revnetId The ID of the revnet having its boost operator replaces.
    function replaceBoostOperatorOf(uint256 _revnetId) external {
        /// Make sure the message sender is the current operator.
        if (!IJBOperatable(address(controller.splitsStore())).operatorStore().hasPermissions({
            operator: msg.sender,
            account: address(this),
            domain: _revnetId,
            permissionIndexes: boostOperatorPermissionIndexes
        }) revert UNAUTHORIZED();

        // Remove operator permission from the old operator.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({ operator: msg.sender, domain: revnetId, permissionIndexes: [] })
        );

        // Give the new operator permission to change the boost recipients.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({ operator: _boostOperator, domain: revnetId, permissionIndexes: boostOperatorPermissionIndexes })
        );
        
    }
}
