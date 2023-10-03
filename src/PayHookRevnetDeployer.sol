// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBController3_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import { IJBPayoutRedemptionPaymentTerminal3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import { IJBFundingCycleBallot } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import { IJBOperatable } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import { IJBSplitAllocator } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import { IJBToken } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol";
import { IJBFundingCycleDataSource3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource3_1_1.sol";
import { JBConstants } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import { JBTokens } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import { JBSplitsGroups } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol";
import { JBOperations } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import { JBFundingCycleData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import { JBFundingCycleMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import { JBPayDelegateAllocation3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import { JBRedemptionDelegateAllocation3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import { JBPayParamsData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import { JBRedeemParamsData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import { JBGlobalFundingCycleMetadata } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import { JBGroupedSplits } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import { JBSplit } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import { JBOperatorData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import { JBFundAccessConstraints } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import { JBProjectMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import { IJBGenericBuybackDelegate } from
    "@jbx-protocol/juice-buyback-delegate/contracts/interfaces/IJBGenericBuybackDelegate.sol";
import { BuybackHookSetupData, RevnetParams, BasicRevnetDeployer } from "./BasicRevnetDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
contract PayHookRevnetDeployer is BasicRevnetDeployer, IJBFundingCycleDataSource3_1_1 {
    /// @notice The data source that returns the correct values for the buyback hook of each network.
    /// @custom:param revnetId The ID of the revnet to which the buyback contract applies.
    mapping(uint256 => IJBGenericBuybackDelegate) public buybackHookOf;

    /// @notice The extensions to include during payments to networks.
    /// @custom:param revnetId The ID of the revnet to which the extensions apply.
    mapping(uint256 => JBPayDelegateAllocation3_1_1[]) public payHooksOf;

    /// @notice The permissions that the provided buyback hook should be granted since it wont be used as the data
    /// source.
    /// This is set once in the constructor to contain only the MINT operation.
    uint256[] public buybackHookPermissionIndexes;

    /// @notice This function gets called when the revnet receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard network payment data. See
    /// https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that network tokens should get minted relative to. This is useful for optionally
    /// customizing how many tokens are issued per payment.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
    /// @return payHooks Amount to be sent to pay hooks instead of adding to local balance. Useful for
    /// auto-routing funds from a treasury as payment come in.
    function payParams(JBPayParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory payHooks)
    {
        // Keep a reference to the hooks that the buyback hook data source provides.
        JBPayDelegateAllocation3_1_1[] memory _buybackHooks;

        // Set the values to be those returned by the buyback hook's data source.
        (weight,, _buybackHooks) = buybackHookOf[_data.projectId].payParams(_data);

        // Check if a buyback hook is used.
        bool _usesBuybackHook = _buybackHooks.length != 0;

        // Cache any other pay hooks to use.
        JBPayDelegateAllocation3_1_1[] memory _payHooks = payHooksOf[_data.projectId];

        // Keep a reference to the number of pay hooks;
        uint256 _numberOfPayHooks = _payHooks.length;

        // Each delegate allocation must run, plus the buyback hook if provided.
        payHooks = new JBPayDelegateAllocation3_1_1[](_numberOfPayHooks + (_usesBuybackHook ? 1 : 0));

        // Add the other expected pay hooks.
        for (uint256 _i; _i < _numberOfPayHooks;) {
            payHooks[_i] = _payHooks[_i];
            unchecked {
                ++_i;
            }
        }

        // Add the buyback hook as the last element.
        if (_usesBuybackHook) payHooks[_numberOfPayHooks] = _buybackHooks[0];

        // Set the default memo.
        memo = _data.memo;
    }

    /// @notice This function is never called, it needs to be included to adhere to the interface.
    function redeemParams(JBRedeemParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256, string memory, JBRedemptionDelegateAllocation3_1_1[] memory)
    {
        _data; // Unused.
        return (0, "", new JBRedemptionDelegateAllocation3_1_1[](0));
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(BasicRevnetDeployer, IERC165)
        returns (bool)
    {
        return _interfaceId == type(IJBFundingCycleDataSource3_1_1).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @param _controller The controller that revnets are made from.
    constructor(IJBController3_1 _controller) BasicRevnetDeployer(_controller) {
        buybackHookPermissionIndexes.push(JBOperations.MINT);
    }

    /// @notice Deploy a basic revnet that also calls other specified pay hooks.
    /// @param _boostOperator The address that will receive the token premint and initial boost, and who is
    /// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
    /// @param _revnetMetadata The metadata containing revnet's info.
    /// @param _name The name of the ERC-20 token being create for the revnet.
    /// @param _symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param _revnetData The data needed to deploy a basic revnet.
    /// @param _terminals The terminals that the network uses to accept payments through.
    /// @param _buybackHookSetupData Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param _payHooks Any hooks that should run when the revnet is paid.
    /// @param _extraCycleMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    function deployPayHookNetworkFor(
        address _boostOperator,
        JBProjectMetadata memory _revnetMetadata,
        string memory _name,
        string memory _symbol,
        RevnetParams memory _revnetData,
        IJBPaymentTerminal[] memory _terminals,
        BuybackHookSetupData memory _buybackHookSetupData,
        JBPayDelegateAllocation3_1_1[] memory _payHooks,
        uint8 _extraCycleMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Package the reserved token splits.
        JBGroupedSplits[] memory _groupedSplits = _makeBoostSplitGroupWith(_boostOperator);

        // Deploy a juicebox for the revnet.
        revnetId = controller.projects().createFor({
            owner: address(this), // This contract should remain the owner, forever.
            metadata: _revnetMetadata
        });

        // Issue the network's ERC-20 token.
        controller.tokenStore().issueFor({ projectId: revnetId, name: _name, symbol: _symbol });

        // Setup the buyback hook.
        _setupBuybackHookOf(revnetId, _buybackHookSetupData);

        // Configure the network's funding cycles using BBD.
        controller.launchFundingCyclesFor({
            projectId: revnetId,
            data: JBFundingCycleData({
                duration: _revnetData.priceCeilingIncreaseFrequency,
                weight: _revnetData.initialIssuanceRate ** 18,
                discountRate: _revnetData.priceCeilingIncreasePercentage,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            metadata: JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: _revnetData.boosts.length == 0 ? 0 : _revnetData.boosts[0].rate, // Set the reserved
                    // rate.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE - _revnetData.priceFloorTaxIntensity, // Set the redemption rate.
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
                // This contract should be the data source.
                dataSource: address(this),
                metadata: _extraCycleMetadata
            }),
            mustStartAtOrAfter: _revnetData.boosts.length == 0 ? 0 : _revnetData.boosts[0].startsAtOrAfter,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: new JBFundAccessConstraints[](0), // Funds can't be accessed by the revnet owner.
            terminals: _terminals,
            memo: "revnet deployed"
        });

        // Keep a reference to the buyback hook.
        buybackHookOf[revnetId] = _buybackHookSetupData.hook;

        // Premint tokens to the boost operator.
        controller.mintTokensOf({
            projectId: revnetId,
            tokenCount: _revnetData.premintTokenAmount * 10 ** 18,
            beneficiary: _boostOperator,
            memo: string.concat("$", _symbol, " preminted"),
            preferClaimedTokens: false,
            useReservedRate: false
        });

        // Give the boost operator permission to change the boost recipients.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({
                operator: _boostOperator,
                domain: revnetId,
                permissionIndexes: boostOperatorPermissionIndexes
            })
        );

        // Give the buyback hook permission to mint on this contract's behald if it doesn't yet have it.
        if (
            !IJBOperatable(address(controller.splitsStore())).operatorStore().hasPermissions(
                address(_buybackHookSetupData.hook), address(this), 0, buybackHookPermissionIndexes
            )
        ) {
            IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
                JBOperatorData({
                    operator: address(_buybackHookSetupData.hook),
                    domain: 0,
                    permissionIndexes: buybackHookPermissionIndexes
                })
            );
        }

        // Store the boost periods so they can be queued via calls to `scheduleNextBoostPeriodOf(...)`.
        _storeBoostsOf(revnetId, _revnetData.boosts);

        // Store the pay hooks.
        _storeHooksOf(revnetId, _payHooks);
    }

    /// @notice Stores pay hooks for the provided revnet.
    /// @param _revnetId The ID of the revnet to which the pay hooks apply.
    /// @param _payHooks The pay hooks to store.
    function _storeHooksOf(uint256 _revnetId, JBPayDelegateAllocation3_1_1[] memory _payHooks) internal {
        // Keep a reference to the number of pay hooks are being stored.
        uint256 _numberOfPayHooks = _payHooks.length;

        // Store the pay hooks.
        for (uint256 _i; _i < _numberOfPayHooks;) {
            payHooksOf[_revnetId][_i] = _payHooks[_i];
            unchecked {
                ++_i;
            }
        }
    }
}
