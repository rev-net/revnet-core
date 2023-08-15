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

    /// @param _directory The directory of terminals and controllers for projects.
    /// @param _delegateDeployer The delegate deployer.
    /// @param _publisher The Croptop publisher that facilitates the permissioned publishing of NFT posts to a Juicebox
    /// project.
    /// @param _controller The controller that projects are made from.
    /// @param _terminal The terminal that projects use to accept payments from.
    /// @param _buybackDelegate The buyback delegate to use.
    constructor(
        CroptopPublisher _publisher,
        IJBDirectory _directory,
        IJBTiered721DelegateDeployer _delegateDeployer,
        IJBController3_1 _controller,
        IJBPayoutRedemptionPaymentTerminal3_1_1 _terminal,
        IJBGenericBuybackDelegate _buybackDelegate
    )
        Tiered721PayAllocatorRetailistJBDeployer(_directory, _delegateDeployer, _controller, _terminal, _buybackDelegate)
    {
        publisher = _publisher;
        croptopPermissionIndexes.push(JB721Operations.ADJUST_TIERS);
    }

    /// @notice Deploy a project with basic Retailism constraints that includes Tiered 721s that the Croptop publisher
    /// can facilitate permissioned posts to, and also calls other pay delegates that are specified.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is
    /// allowed to change the allocated reserved rate distribution.
    /// @param _projectMetadata The metadata containing project info.
    /// @param _name The name of the ERC-20 token being create for the project.
    /// @param _symbol The symbol of the ERC-20 token being created for the project.
    /// @param _deployTiered721DelegateData Structure containing data necessary for delegate deployment.
    /// @param _otherDelegateAllocations Any pay delegate allocations that should run when the project is paid.
    /// @param _extraFundingCycleMetadata Extra metadata to attach to the funding cycle for the delegates to use.
    /// @param _allowedPosts The type of posts that the project should allow.
    /// @return projectId The ID of the newly created Retailist project.
    function deployCroptopTiered721PayAllocatorProjectFor(
        address _operator,
        JBProjectMetadata memory _projectMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams calldata _data,
        JBDeployTiered721DelegateData calldata _deployTiered721DelegateData,
        JBPayDelegateAllocation3_1_1[] calldata _otherDelegateAllocations,
        uint8 _extraFundingCycleMetadata,
        AllowedPost[] calldata _allowedPosts
    )
        public
        returns (uint256 projectId)
    {
        projectId = super.deployTiered721PayAllocatorProjectFor(
            _operator,
            _projectMetadata,
            _name,
            _symbol,
            _data,
            _deployTiered721DelegateData,
            _otherDelegateAllocations,
            _extraFundingCycleMetadata
        );

        // Configure allowed posts.
        if (_allowedPosts.length != 0) publisher.configureFor(projectId, _allowedPosts);

        // Give the croptop publisher permission to post on this contract's behalf.
        IJBOperatable(address(directory)).operatorStore().setOperator(
            JBOperatorData({
                operator: address(publisher),
                domain: projectId,
                permissionIndexes: croptopPermissionIndexes
            })
        );
    }
}
