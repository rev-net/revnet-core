// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CroptopPublisher, AllowedPost } from "@croptop/publisher/src/CroptopPublisher.sol";
import { JB721Operations } from "@jbx-protocol/juice-721-delegate/contracts/libraries/JB721Operations.sol";
import { IJBTiered721DelegateDeployer } from
    "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateDeployer.sol";
import { JBDeployTiered721DelegateData } from
    "@jbx-protocol/juice-721-delegate/contracts/structs/JBDeployTiered721DelegateData.sol";
import { IJBController3_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import { IJBDirectory } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBOperatable } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import { IJBPayoutRedemptionPaymentTerminal3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import { JBOperatorData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import { JBPayDelegateAllocation3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import { JBProjectMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import { IJBGenericBuybackDelegate } from
    "@jbx-protocol/juice-buyback-delegate/contracts/interfaces/IJBGenericBuybackDelegate.sol";
import {
    BasicRetailistJBParams,
    Tiered721PayAllocatorRetailistJBDeployer
} from "./Tiered721PayAllocatorRetailistJBDeployer.sol";

/// @notice A contract that facilitates deploying a basic Retailist treasury that also can mint tiered 721s via a
/// Croptop proxy.
contract CroptopTiered721PayAllocatorRetailistJBDeployer is Tiered721PayAllocatorRetailistJBDeployer {
    /// @notice The Croptop publisher that facilitates the permissioned publishing of NFT posts to a Juicebox project.
    CroptopPublisher public publisher;

    /// @notice The permissions that the provided _operator should be granted. This is set once in the constructor to
    /// contain only the SET_SPLITS operation.
    uint256[] public croptopPermissionIndexes;

    /// @param _directory The directory of terminals and controllers for networks.
    /// @param _delegateDeployer The delegate deployer.
    /// @param _publisher The Croptop publisher that facilitates the permissioned publishing of NFT posts to a Juicebox
    /// network.
    /// @param _controller The controller that networks are made from.
    constructor(
        CroptopPublisher _publisher,
        IJBDirectory _directory,
        IJBTiered721DelegateDeployer _delegateDeployer,
        IJBController3_1 _controller
    )
        Tiered721PayAllocatorRetailistJBDeployer(_directory, _delegateDeployer, _controller)
    {
        publisher = _publisher;
        croptopPermissionIndexes.push(JB721Operations.ADJUST_TIERS);
    }

    /// @notice Deploy a network with basic Retailism constraints that includes Tiered 721s that the Croptop publisher
    /// can facilitate permissioned posts to, and also calls other pay delegates that are specified.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is
    /// allowed to change the allocated reserved rate distribution.
    /// @param _networkMetadata The metadata containing network info.
    /// @param _name The name of the ERC-20 token being create for the network.
    /// @param _symbol The symbol of the ERC-20 token being created for the network.
    /// @param _data The data needed to deploy a basic retailist network.
    /// @param _terminals The terminals that the network uses to accept payments through.
    /// @param _buybackDelegate The buyback delegate to use when determining the best price for new participants.
    /// @param _deployTiered721DelegateData Structure containing data necessary for delegate deployment.
    /// @param _otherDelegateAllocations Any pay delegate allocations that should run when the network is paid.
    /// @param _extraFundingCycleMetadata Extra metadata to attach to the funding cycle for the delegates to use.
    /// @param _allowedPosts The type of posts that the network should allow.
    /// @return networkId The ID of the newly created Retailist network.
    function deployCroptopTiered721PayAllocatorNetworkFor(
        address _operator,
        JBProjectMetadata memory _networkMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams memory _data,
        IJBPaymentTerminal[] memory _terminals,
        IJBGenericBuybackDelegate _buybackDelegate,
        JBDeployTiered721DelegateData memory _deployTiered721DelegateData,
        JBPayDelegateAllocation3_1_1[] memory _otherDelegateAllocations,
        uint8 _extraFundingCycleMetadata,
        AllowedPost[] memory _allowedPosts
    )
        public
        returns (uint256 networkId)
    {
        networkId = super.deployTiered721PayAllocatorNetworkFor(
            _operator,
            _networkMetadata,
            _name,
            _symbol,
            _data,
            _terminals,
            _buybackDelegate,
            _deployTiered721DelegateData,
            _otherDelegateAllocations,
            _extraFundingCycleMetadata
        );

        // Configure allowed posts.
        if (_allowedPosts.length != 0) publisher.configureFor(networkId, _allowedPosts);

        // Give the croptop publisher permission to post on this contract's behalf.
        IJBOperatable(address(directory)).operatorStore().setOperator(
            JBOperatorData({
                operator: address(publisher),
                domain: networkId,
                permissionIndexes: croptopPermissionIndexes
            })
        );
    }
}
