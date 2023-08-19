// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IJBTiered721Delegate } from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol";
import { IJBTiered721DelegateDeployer } from
    "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateDeployer.sol";
import { JBDeployTiered721DelegateData } from
    "@jbx-protocol/juice-721-delegate/contracts/structs/JBDeployTiered721DelegateData.sol";
import { IJBController3_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import { IJBDirectory } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBPayoutRedemptionPaymentTerminal3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import { IJBPayDelegate3_1_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate3_1_1.sol";
import { JBPayDelegateAllocation3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import { JBProjectMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import { IJBGenericBuybackDelegate } from
    "@jbx-protocol/juice-buyback-delegate/contracts/interfaces/IJBGenericBuybackDelegate.sol";
import { BasicRetailistJBParams, PayAllocatorRetailistJBDeployer } from "./PayAllocatorRetailistJBDeployer.sol";

/// @notice A contract that facilitates deploying a basic Retailist treasury that also can mint tiered 721s.
contract Tiered721PayAllocatorRetailistJBDeployer is PayAllocatorRetailistJBDeployer {
    /// @notice The directory of terminals and controllers for networks.
    IJBDirectory public immutable directory;

    /// @notice The contract responsible for deploying the delegate.
    IJBTiered721DelegateDeployer public immutable delegateDeployer;

    /// @param _directory The directory of terminals and controllers for networks.
    /// @param _delegateDeployer The delegate deployer.
    /// @param _controller The controller that networks are made from.
    constructor(
        IJBDirectory _directory,
        IJBTiered721DelegateDeployer _delegateDeployer,
        IJBController3_1 _controller
    )
        PayAllocatorRetailistJBDeployer(_controller)
    {
        directory = _directory;
        delegateDeployer = _delegateDeployer;
    }

    /// @notice Deploy a network with basic Retailism constraints that includes Tiered 721s and also calls other pay
    /// delegates that are specified.
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
    /// @return networkId The ID of the newly created Retailist network.
    function deployTiered721PayAllocatorNetworkFor(
        address _operator,
        JBProjectMetadata memory _networkMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams memory _data,
        IJBPaymentTerminal[] memory _terminals,
        IJBGenericBuybackDelegate _buybackDelegate,
        JBDeployTiered721DelegateData memory _deployTiered721DelegateData,
        JBPayDelegateAllocation3_1_1[] memory _otherDelegateAllocations,
        uint8 _extraFundingCycleMetadata
    )
        public
        returns (uint256 networkId)
    {
        // Get the network ID, optimistically knowing it will be one greater than the current count.
        networkId = directory.projects().count() + 1;

        // Keep a reference to the number of delegate allocations passed in.
        uint256 _numberOfOtherDelegateAllocations = _otherDelegateAllocations.length;

        // Track an updated list of delegate allocations that'll also fit the Tiered 721 Delegate allocation.
        JBPayDelegateAllocation3_1_1[] memory _delegateAllocations =
            new JBPayDelegateAllocation3_1_1[](_numberOfOtherDelegateAllocations + 1);

        // Repopulate the updated list with the params passed in.
        for (uint256 _i; _i < _numberOfOtherDelegateAllocations;) {
            _delegateAllocations[_i] = _otherDelegateAllocations[_i];
            unchecked {
                ++_i;
            }
        }

        {
            // Deploy the delegate contract.
            IJBTiered721Delegate _delegate = delegateDeployer.deployDelegateFor(networkId, _deployTiered721DelegateData);

            // Add the Tiered 721 Allocation at the end.
            _delegateAllocations[_numberOfOtherDelegateAllocations] = JBPayDelegateAllocation3_1_1({
                delegate: IJBPayDelegate3_1_1(address(_delegate)),
                amount: 0,
                metadata: bytes("")
            });
        }

        super.deployPayAllocatorNetworkFor(
            _operator,
            _networkMetadata,
            _name,
            _symbol,
            _data,
            _terminals,
            _buybackDelegate,
            _delegateAllocations,
            _extraFundingCycleMetadata
        );
    }
}
