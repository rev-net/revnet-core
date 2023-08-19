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
import { BuybackDelegateSetup, BasicRetailistJBParams, BasicRetailistJBDeployer } from "./BasicRetailistJBDeployer.sol";

/// @notice A contract that facilitates deploying a basic Retailist treasury that also calls other pay delegates that
/// are specified when the network is deployed.
contract PayAllocatorRetailistJBDeployer is BasicRetailistJBDeployer, IJBFundingCycleDataSource3_1_1 {
    /// @notice The data source that returns the correct values for the Buyback Delegate of each network.
    /// @custom:param networkId The ID of the network to which the Buyback Delegate allocations apply.
    mapping(uint256 => IJBGenericBuybackDelegate) public buybackDelegateDataSourceOf;

    /// @notice The delegate allocations to include during payments to networks.
    /// @custom:param networkId The ID of the network to which the delegate allocations apply.
    mapping(uint256 => JBPayDelegateAllocation3_1_1[]) public delegateAllocationsOf;

    /// @notice The permissions that the provided buyback delegate should be granted since it wont be used as the data
    /// source. This is set once in the constructor to
    /// contain only the MINT operation.
    uint256[] public buybackDelegatePermissionIndexes;

    /// @notice This function gets called when the network receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard network payment data. See
    /// https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that network tokens should get minted relative to. This is useful for optionally
    /// customizing how many tokens are issued per payment.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to local balance. Useful for
    /// auto-routing funds from a treasury as payment come in.
    function payParams(JBPayParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations)
    {
        // Keep a reference to the delegate allocatios that the Buyback Data Source provides.
        JBPayDelegateAllocation3_1_1[] memory _buybackDelegateAllocations;

        // Set the values to be those returned by the Buyback Data Source.
        (weight,, _buybackDelegateAllocations) = buybackDelegateDataSourceOf[_data.projectId].payParams(_data);

        // Keep a reference to the number of buyback delegation allocations are returned.
        bool _usesBuybackDelegate = _buybackDelegateAllocations.length != 0;

        // Cache the delegate allocations.
        JBPayDelegateAllocation3_1_1[] memory _delegateAllocations = delegateAllocationsOf[_data.projectId];

        // Keep a reference to the number of delegate allocations;
        uint256 _numberOfDelegateAllocations = _delegateAllocations.length;

        // Each delegate allocation must run, plus the buyback delegate.
        delegateAllocations =
            new JBPayDelegateAllocation3_1_1[](_numberOfDelegateAllocations + (_usesBuybackDelegate ? 1 : 0));

        // All the rest of the delegate allocations the network expects.
        for (uint256 _i; _i < _numberOfDelegateAllocations;) {
            delegateAllocations[_i] = _delegateAllocations[_i];
            unchecked {
                ++_i;
            }
        }

        // Add the buyback delegate as the last element.
        if (_usesBuybackDelegate) delegateAllocations[_numberOfDelegateAllocations] = _buybackDelegateAllocations[0];

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
        override(BasicRetailistJBDeployer, IERC165)
        returns (bool)
    {
        return _interfaceId == type(IJBFundingCycleDataSource3_1_1).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @param _controller The controller tha networks are made from.
    constructor(IJBController3_1 _controller) BasicRetailistJBDeployer(_controller) {
        buybackDelegatePermissionIndexes.push(JBOperations.MINT);
    }

    /// @notice Deploy a network with basic Retailism constraints that also calls other pay delegates that are
    /// specified.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is
    /// allowed to change the allocated reserved rate distribution.
    /// @param _networkMetadata The metadata containing network info.
    /// @param _name The name of the ERC-20 token being create for the network.
    /// @param _symbol The symbol of the ERC-20 token being created for the network.
    /// @param _data The data needed to deploy a basic retailist network.
    /// @param _terminals The terminals that the network uses to accept payments through.
    /// @param _buybackDelegateSetup Info for setting up the buyback delegate to use when determining the best price for new participants.
    /// @param _delegateAllocations Any pay delegate allocations that should run when the network is paid.
    /// @param _extraFundingCycleMetadata Extra metadata to attach to the funding cycle for the delegates to use.
    /// @return networkId The ID of the newly created Retailist network.
    function deployPayAllocatorNetworkFor(
        address _operator,
        JBProjectMetadata memory _networkMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams memory _data,
        IJBPaymentTerminal[] memory _terminals,
        BuybackDelegateSetup memory _buybackDelegateSetup,
        JBPayDelegateAllocation3_1_1[] memory _delegateAllocations,
        uint8 _extraFundingCycleMetadata
    )
        public
        returns (uint256 networkId)
    {
        // Package the reserved token splits.
        JBGroupedSplits[] memory _groupedSplits = _makeDevTaxSplitGroupWith(_operator);

        // Deploy a network.
        networkId = controller.projects().createFor({
            owner: address(this), // This contract should remain the owner, forever.
            metadata: _networkMetadata
        });

        // Issue the network's ERC-20 token.
        controller.tokenStore().issueFor({ projectId: networkId, name: _name, symbol: _symbol });

        // Setup the buyback delegate.
        _setupBuybackDelegate(networkId, _buybackDelegateSetup);

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
                reservedRate: _data.devTaxPeriods.length == 0 ? 0 : _data.devTaxPeriods[0].rate, // Set the reserved
                    // rate.
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
                // This contract should be the data source.
                dataSource: address(this),
                metadata: _extraFundingCycleMetadata
            }),
            mustStartAtOrAfter: _data.devTaxPeriods.length == 0 ? 0 : _data.devTaxPeriods[0].startsAtOrAfter,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: new JBFundAccessConstraints[](0), // Funds can't be accessed by the network
                // owner.
            terminals: _terminals,
            memo: "Deployed Retailist network"
        });

        // Keep a reference to this data source.
        buybackDelegateDataSourceOf[networkId] = _buybackDelegateSetup.delegate;

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

        // Give the buyback delegate permission to mint on this contract's behald if it doesn't yet have it.
        if (
            !IJBOperatable(address(controller.splitsStore())).operatorStore().hasPermissions(
                address(_buybackDelegateSetup.delegate), address(this), 0, buybackDelegatePermissionIndexes
            )
        ) {
            IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
                JBOperatorData({
                    operator: address(_buybackDelegateSetup.delegate),
                    domain: 0,
                    permissionIndexes: buybackDelegatePermissionIndexes
                })
            );
        }

        // Store the dev tax periods so they can be queued via calls to `scheduleNextDevTaxPeriodOf(...)`.
        _storeDevTaxPeriodsOf(networkId, _data.devTaxPeriods, _data.generationDuration);

        // Store the delegate allocations.
        _storeDelegateAllocationsOf(networkId, _delegateAllocations);
    }

    /// @notice Stores delegate allocations for the provided network.
    /// @param _networkId The ID to which the delegate allocations apply.
    /// @param _delegateAllocations The delegate allocations to store.
    function _storeDelegateAllocationsOf(
        uint256 _networkId,
        JBPayDelegateAllocation3_1_1[] memory _delegateAllocations
    )
        internal
    {
        // Store the pay delegate allocations.
        uint256 _numberOfDelegateAllocations = _delegateAllocations.length;

        for (uint256 _i; _i < _numberOfDelegateAllocations;) {
            delegateAllocationsOf[_networkId][_i] = _delegateAllocations[_i];
            unchecked {
                ++_i;
            }
        }
    }
}
