// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IJBTerminal } from "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBTerminal.sol";
import { IJBController } from "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBController.sol";
import { IJBMultiTerminal } from
    "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBMultiTerminal.sol";
import { IJBRulesetApprovalHook } from "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBRulesetApprovalHook.sol";
import { IJBPermissioned } from "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBPermissioned.sol";
import { IJBSplitHook } from "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBSplitHook.sol";
import { IJBToken } from "@jbx-protocol/juice-contracts-v4/contracts/interfaces/IJBToken.sol";
import { JBPermissions } from "@jbx-protocol/juice-contracts-v4/contracts/libraries/JBPermissions.sol";
import { JBConstants } from "@jbx-protocol/juice-contracts-v4/contracts/libraries/JBConstants.sol";
import { JBSplitGroupIds } from "@jbx-protocol/juice-contracts-v4/contracts/libraries/JBSplitGroupIds.sol";
import { JBRulesetData } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBRulesetData.sol";
import { JBRulesetMetadata } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBRulesetMetadata.sol";
import { JBRuleset } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBRuleset.sol";
import {JBTerminalConfig} from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBTerminalConfig.sol";
import { JBGroupedSplits } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBGroupedSplits.sol";
import { JBSplit } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBSplit.sol";
import { JBPermissionsData } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBPermissionsData.sol";
import { JBFundAccessLimitGroup } from "@jbx-protocol/juice-contracts-v4/contracts/structs/JBFundAccessLimitGroup.sol";
import { IJBGenericBuybackDelegate } from
    "@jbx-protocol/juice-buyback-delegate/contracts/interfaces/IJBGenericBuybackDelegate.sol";
import { JBBuybackDelegateOperations } from
    "@jbx-protocol/juice-buyback-delegate/contracts/libraries/JBBuybackDelegateOperations.sol";

/// @custom:member rate The percentage of newly issued tokens that should be reserved for the _boostOperator, out of
/// 10_000 (JBConstants.MAX_RESERVED_RATE).
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

/// @custom:member hook The buyback hook to use.
/// @custom:member pools The pools to setup on the given buyback contract.
struct BuybackHookSetupData {
    IJBGenericBuybackDelegate hook;
    BuybackPool[] pools;
}

/// @custom:member initialIssuanceRate The number of tokens that should be minted initially per 1 currency unit
/// contributed to the
/// revnet. This should _not_ be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member premintTokenAmount The number of tokens that should be preminted to the _boostOperator. This should
/// _not_
/// be specified as a fixed point number with 18 decimals, this will be applied internally.
/// @custom:member priceCeilingIncreaseFrequency The number of seconds between applied price ceiling increases. This should be at least
/// 24 hours.
/// @custom:member priceCeilingIncreasePercentage The rate at which the price ceiling should increase over time, thus
/// decreasing the rate of issuance. This percentage is out
/// of 1_000_000_000 (JBConstants.MAX_DISCOUNT_RATE). 0% corresponds to no price ceiling increase, everyone is treated
/// equally over time.
/// @custom:member priceFloorTaxIntensity The factor determining how much each token can reclaim from the revnet once redeemed.
/// This percentage is out of 10_000 (JBConstants.MAX_REDEMPTION_RATE). 0% corresponds to no floor tax when
/// redemptions are made, everyone's redemptions are treated equally. The higher the intensity, the higher the tax.
/// @custom:member boosts The periods of distinguished boosting that should be applied over time.
struct RevnetParams {
    uint256 initialIssuanceRate;
    uint256 premintTokenAmount;
    uint256 priceCeilingIncreaseFrequency;
    uint256 priceCeilingIncreasePercentage;
    uint256 priceFloorTaxIntensity;
    Boost[] boosts;
}

/// @notice A contract that facilitates deploying a basic Revnet.
contract BasicRevnetDeployer is IERC721Receiver {
    error RECONFIGURATION_ALREADY_SCHEDULED();
    error RECONFIGURATION_NOT_POSSIBLE();
    error BAD_BOOST_SEQUENCE();
    error UNAUTHORIZED();

    /// @notice The boosts for each network.
    /// @dev A basic revnet consists of cycles defined by scheduled boosts. The only changes between them are in their
    /// reserved rate.
    /// @custom:param _revnetId The ID of the revnet to which the boosts apply.
    mapping(uint256 _revnetId => Boost[]) internal _boostsOf;

    /// @notice The controller that networks are made from.
    IJBController public immutable controller;

    /// @notice The permissions that the provided _boostOperator should be granted. This is set once in the constructor
    /// to contain only the SET_SPLITS operation.
    uint256[] public boostOperatorPermissionIndexes;

    /// @notice The current index of the boost that each revnet is in, relative to _boostsOf.
    /// @custom:param _revnetId The ID of the revnet to which the boost applies.
    mapping(uint256 _revnetId => uint256) public currentBoostNumberOf;

    /// @notice The boosts for each network.
    /// @dev A basic revnet consists of cycles defined by scheduled boost periods. The only changes between them are in
    /// their reserved rate.
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

    /// @param _controller The controller that revnets are made from.
    constructor(IJBController _controller) {
        controller = _controller;
        boostOperatorPermissionIndexes.push(JBPermissions.SET_SPLITS);
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
    /// @param _buybackHookSetupData Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @return revnetId The ID of the newly created revnet.
    function deployRevnetFor(
        address _boostOperator,
        string memory _revnetMetadata,
        string memory _name,
        string memory _symbol,
        RevnetParams memory _revnetData,
        JBTerminalConfig[] memory terminalConfigurations,
        BuybackHookSetupData memory _buybackHookSetupData
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
        controller.deployERC20For({ projectId: revnetId, name: _name, symbol: _symbol });

        // Setup the buyback hook.
        _setupBuybackHookOf(revnetId, _buybackHookSetupData);

        // Package up the ruleset configuration.
        JBRulesetConfig[] memory rulesetConfigurations = new JBRulesetConfig[](1);
        rulesetConfigurations[0].mustStartAtOrAfter = _revnetData.boosts.length == 0 ? 0 : _revnetData.boosts[0].startsAtOrAfter;
        rulesetConfigurations[0].data = JBRulesetData({
                duration: _revnetData.priceCeilingIncreaseFrequency,
                weight: _revnetData.initialIssuanceRate * 10 ** 18,
                decayRate: _revnetData.priceCeilingIncreasePercentage,
                hook: IJBRulesetApprovalHook(address(0))
            });
        rulesetConfigurations[0].metadata = JBRulesetMetadata({
                reservedRate: _revnetData.boosts.length == 0 ? 0 : _revnetData.boosts[0].rate, // Set the reserved rate
                    // that'll model the boost periods.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE - _revnetData.priceFloorTaxIntensity, // Set the redemption
                    // rate.
                baseCurrency: 0,
                pausePay: false,
                pauseCreditTransfers: false,
                allowOwnerMinting: true, // Allow this contract to premint tokens as the network owner.
                allowTerminalMigration: false,
                allowSetTerminals: false,
                allowControllerMigration: false,
                allowSetController: false,
                holdFees: false,
                useTotalSurplusForRedemptions: false,
                useDataHookForPay: true, // Use the buyback delegate data source.
                useDataHookForRedeem: false,
                dataSource: address(_buybackHookSetupData.hook),
                metadata: 0
            });

        rulesetConfigurations[0].splitGroups = _groupedSplits;
        rulesetConfigurations[0].fundAccessLimitGroups =  new JBFundAccessLimitGroup[](0);

        // Configure the revnet's cycles using BBD.
        controller.launchRulesetsFor({
            projectId: revnetId,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: terminalConfigurations,
            memo: "revnet deployed"
        });

        // Premint tokens to the boost operator if needed.
        if (_revnetData.premintTokenAmount > 0)
            controller.mintTokensOf({
                projectId: revnetId,
                tokenCount: _revnetData.premintTokenAmount * 10 ** 18,
                beneficiary: _boostOperator,
                memo: string.concat("$", _symbol, " preminted"),
                useReservedRate: false
            });

        // Give the boost operator permission to change the boost recipients.
        IJBPermissioned(address(controller.SPLITS())).PERMISSIONS().setPermissions(
            JBPermissionsData({
                operator: _boostOperator,
                domain: revnetId,
                permissionIndexes: boostOperatorPermissionIndexes
            })
        );

        // Store the boost periods so they can be queued via calls to `scheduleNextBoostPeriodOf(...)`.
        _storeBoostsOf(revnetId, _revnetData.boosts);
    }

    // /// @notice Schedules the next boost specified when the revnet was deployed.
    // /// @param _revnetId The ID of the revnet having its next boost scheduled.
    // function scheduleNextBoostOf(uint256 _revnetId) external {
    //     // Get a reference to the latest configured cycle and its metadata.
    //     (JBRuleset memory _latestFundingCycleConfiguration, JBRulesetMetadata memory _metadata,) =
    //         controller.latestConfiguredFundingCycleOf(_revnetId);

    //     // Get a reference to the next boost number, while incrementing the stored value. Zero indexed.
    //     uint256 _nextBoostNumber = currentBoostNumberOf[_revnetId]++;

    //     // Get a reference to the number of boosts there are. 1 indexed.
    //     uint256 _numberOfBoosts = _boostsOf[_revnetId].length;

    //     // Make sure the latest cycle configured started in the past, and that there are more boosts to schedule.
    //     if (
    //         _numberOfBoosts == 0 || _nextBoostNumber == _numberOfBoosts
    //             || _latestFundingCycleConfiguration.start >= block.timestamp
    //     ) revert RECONFIGURATION_ALREADY_SCHEDULED();

    //     // Get a reference to the next boost.
    //     Boost memory _boost = _boostsOf[_revnetId][_nextBoostNumber];

    //     // Schedule a cycle reconfiguration.
    //     controller.reconfigureFundingCyclesOf({
    //         projectId: _revnetId,
    //         data: JBRulesetData({
    //             duration: _latestFundingCycleConfiguration.duration,
    //             weight: 0, // Inherit the weight of the current funding cycle.
    //             discountRate: _latestFundingCycleConfiguration.discountRate,
    //             ballot: IJBRulesetApprovalHook(address(0))
    //         }),
    //         metadata: JBRulesetMetadata({
    //             global: JBGlobalFundingCycleMetadata({
    //                 allowSetTerminals: false,
    //                 allowSetController: false,
    //                 pauseTransfers: false
    //             }),
    //             reservedRate: _boost.rate, // Set the reserved rate to model the boost.
    //             redemptionRate: _metadata.redemptionRate, // Set the same redemption rate.
    //             ballotRedemptionRate: 0, // There will never be an active ballot, so this can be left off.
    //             pausePay: false,
    //             pauseDistributions: false,
    //             pauseRedeem: false,
    //             pauseBurn: false,
    //             allowMinting: false,
    //             allowTerminalMigration: false,
    //             allowControllerMigration: false,
    //             holdFees: false,
    //             preferClaimedTokenOverride: false,
    //             useTotalOverflowForRedemptions: false,
    //             useDataSourceForPay: false,
    //             useDataSourceForRedeem: false,
    //             dataSource: _metadata.dataSource,
    //             metadata: _metadata.metadata
    //         }),
    //         mustStartAtOrAfter: _boost.startsAtOrAfter,
    //         groupedSplits: _copyBoostSplitGroupFrom(_revnetId, _latestFundingCycleConfiguration.configuration),
    //         fundAccessConstraints: new JBFundAccessLimitGroup[](0),
    //         memo: "revnet boost scheduled"
    //     });
    // }

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
    /// @return splitGroups The grouped splits to be used in a configuration.
    function _makeBoostSplitGroupWith(address _boostOperator)
        internal
        pure
        returns (JBSplitGroup[] memory splitGroups)
    {
        // Package the reserved token splits.
        splitGroups = new JBSplitGroup[](1);

        // Make the splits.

        // Make a new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory _splits = new JBSplit[](1);

        // Send the _boostOperator all of the reserved tokens. They'll be able to change this later whenever they wish.
        _splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(_boostOperator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        splitGroups[0] = JBSplitGroup({ groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: _splits });
    }

    /// @notice Copies a group of splits from  the one stored in the provided configuration.
    /// @param _revnetId The ID of the revnet to which the splits apply.
    /// @param _baseConfiguration The configuration to copy configurations from.
    /// @return splitGroups The grouped splits to be used in a configuration.
    function _copyBoostSplitGroupFrom(
        uint256 _revnetId,
        uint256 _baseConfiguration
    )
        internal
        view
        returns (JBSplitGroup[] memory splitGroups)
    {
        // Package the reserved token splits.
        splitGroups = new JBSplitGroup[](1);

        // Make new splits specifying where the reserved tokens will be sent.
        JBSplit[] memory _splits =
            controller.SPLITS().splitsOf(_revnetId, _baseConfiguration, JBSplitGroupIds.RESERVED_TOKENS);

        splitGroups[0] = JBSplitGroup({ groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: _splits });
    }

    /// @notice Sets up a buyback hook.
    /// @param _revnetId The ID of the revnet to which the buybacks should apply.
    /// @param _buybackHookSetupData Data used to setup pools that'll be used to buyback tokens from if an optimal price
    /// is presented.
    function _setupBuybackHookOf(uint256 _revnetId, BuybackHookSetupData memory _buybackHookSetupData) internal {
        // Get a reference to the number of pools that need setting up.
        uint256 _numberOfPoolsToSetup = _buybackHookSetupData.pools.length;

        // Keep a reference to the pool being iterated on.
        BuybackPool memory _pool;

        for (uint256 _i; _i < _numberOfPoolsToSetup;) {
            // Get a reference to the pool being iterated on.
            _pool = _buybackHookSetupData.pools[_i];

            // Set the pool for the buyback contract.
            _buybackHookSetupData.hook.setPoolFor({
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
    function _storeBoostsOf(uint256 _revnetId, Boost[] memory _boosts) internal {
        // Keep a reference to the number of boosts.
        uint256 _numberOfBoosts = _boosts.length;

        // Store the boost that aren't initially scheduled. Separate transactions to `scheduleNextBoostPeriodOf` must be called to schedule each of
        // them.
        if (_numberOfBoosts > 1) {
            for (uint256 _i = 1; _i < _numberOfBoosts;) {
                // Store the boost.
                _boostsOf[_revnetId].push(_boosts[_i]);

                unchecked {
                    ++_i;
                }
            }
        }
    }

    /// @notice A revnet's boost operator can replace itself.
    /// @param _revnetId The ID of the revnet having its boost operator replaces.
    /// @param _newBoostOperator The address of the new boost operator.
    function replaceBoostOperatorOf(uint256 _revnetId, address _newBoostOperator) external {
        /// Make sure the message sender is the current operator.
        if (
            !IJBPermissioned(address(controller.SPLITS())).OPERATOR().hasPermissions({
                operator: msg.sender,
                account: address(this),
                projectId: _revnetId,
                permissionIndexes: boostOperatorPermissionIndexes
            })
        ) revert UNAUTHORIZED();

        // Remove operator permission from the old operator.
        IJBPermissioned(address(controller.SPLITS())).PERMISSIONS().setPermissionsForOperator(
            JBPermissionsData({ operator: msg.sender, projectId: _revnetId, permissionIndexes: new uint256[](0) })
        );

        // Give the new operator permission to change the boost recipients.
        IJBPermissioned(address(controller.SPLITS())).PERMISSIONS().setPermissionsForOperator(
            JBPermissionsData({
                operator: _newBoostOperator,
                projectId: _revnetId,
                permissionIndexes: boostOperatorPermissionIndexes
            })
        );
    }
}
