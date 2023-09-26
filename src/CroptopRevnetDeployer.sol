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
    BuybackHookSetupData,
    RevnetParams,
    Tiered721RevnetDeployer
} from "./Tiered721RevnetDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s via a croptop proxy.
contract CroptopRevnetDeployer is Tiered721RevnetDeployer {

    /// @notice The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    CroptopPublisher public publisher;

    /// @notice The permissions that the croptop publisher should be granted. This is set once in the constructor to contain only the ADJUST_TIERS operation.
    uint256[] public croptopPermissionIndexes;

    /// @param _directory The directory of terminals and controllers for revnets.
    /// @param _tiered721HookDeployer The tiered 721 hook deployer.
    /// @param _controller The controller that revnets are made from.
    /// @param _publisher The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    constructor(
        IJBDirectory _directory,
        IJBTiered721DelegateDeployer _tiered721HookDeployer,
        IJBController3_1 _controller,
        CroptopPublisher _publisher
    )
        Tiered721RevnetDeployer(_directory, _tiered721HookDeployer, _controller)
    {
        publisher = _publisher;
        croptopPermissionIndexes.push(JB721Operations.ADJUST_TIERS);
    }

    /// @notice Deploy a basic revnet that includes Tiered 721s the Croptop publisher
    /// can facilitate permissioned posts to, and also calls other specified pay hooks.
    /// @param _boostOperator The address that will receive the token premint and initial boost, and who is
    /// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
    /// @param _revnetMetadata The metadata containing revnet's info.
    /// @param _name The name of the ERC-20 token being create for the revnet.
    /// @param _symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param _revnetData The data needed to deploy a basic revnet.
    /// @param _terminals The terminals that the network uses to accept payments through.
    /// @param _buybackHookSetupData Data used for setting up the buyback hook to use when determining the best price for new participants.
    /// @param _tiered721SetupData Structure containing data necessary for delegate deployment.
    /// @param _otherPayHooks Any other hooks that should run when the revnet is paid.
    /// @param _extraCycleMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @param _allowedPosts The type of posts that the network should allow.
    /// @return revnetId The ID of the newly created revnet.    
    function deployCroptopRevnetFor(
        address _boostOperator,
        JBProjectMetadata memory _revnetMetadata,
        string memory _name,
        string memory _symbol,
        RevnetParams memory _revnetData,
        IJBPaymentTerminal[] memory _terminals,
        BuybackHookSetupData memory _buybackHookSetupData,
        JBDeployTiered721DelegateData memory _tiered721SetupData,
        JBPayDelegateAllocation3_1_1[] memory _otherPayHooks,
        uint8 _extraCycleMetadata,
        AllowedPost[] memory _allowedPosts
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet with tiered 721 hooks.
        revnetId = super.deployTiered721RevnetFor(
            _boostOperator,
            _revnetMetadata,
            _name,
            _symbol,
            _revnetData,
            _terminals,
            _buybackHookSetupData,
            _tiered721SetupData,
            _otherPayHooks,
            _extraCycleMetadata
        );

        // Configure allowed posts.
        if (_allowedPosts.length != 0) publisher.configureFor(revnetId, _allowedPosts);

        // Give the croptop publisher permission to post on this contract's behalf.
        IJBOperatable(address(directory)).operatorStore().setOperator(
            JBOperatorData({
                operator: address(publisher),
                domain: revnetId,
                permissionIndexes: croptopPermissionIndexes
            })
        );
    }
}
