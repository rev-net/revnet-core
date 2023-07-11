// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBTiered721Delegate} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol";
import {IJBTiered721DelegateDeployer} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateDeployer.sol";
import {JBDeployTiered721DelegateData} from "@jbx-protocol/juice-721-delegate/contracts/structs/JBDeployTiered721DelegateData.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBPayoutRedemptionPaymentTerminal3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBToken} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol";
import {IJBFundingCycleDataSource3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource3_1_1.sol";
import {IJBPayDelegate3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate3_1_1.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import {JBConstants} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import {JBSplitsGroups} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {JBPayDelegateAllocation3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import {JBRedemptionDelegateAllocation3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {BasicRetailistJBParams, PayAllocatorRetailistJBDeployer} from "./PayAllocatorRetailistJBDeployer.sol";

/// @notice A contract that facilitates deploying a basic Retailist treasury that also can mint tiered 721s.
contract Tiered721PayAllocatorRetailistJBDeployer is PayAllocatorRetailistJBDeployer {

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable directory;

    /// @notice The contract responsible for deploying the delegate.
    IJBTiered721DelegateDeployer public immutable delegateDeployer;

    /// @param _directory The directory of terminals and controllers for projects.
    /// @param _delegateDeployer The delegate deployer.
    /// @param _controller The controller that projects are made from.
    /// @param _terminal The terminal that projects use to accept payments from.
    constructor(IJBDirectory _directory, IJBTiered721DelegateDeployer _delegateDeployer, IJBController3_1 _controller, IJBPayoutRedemptionPaymentTerminal3_1_1 _terminal) PayAllocatorRetailistJBDeployer(_controller, _terminal) {
      directory = _directory;
      delegateDeployer = _delegateDeployer;
    }

    /// @notice Deploy a project with basic Retailism constraints that also calls other pay delegates that are specified.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is allowed to change the allocated reserved rate distribution.
    /// @param _projectMetadata The metadata containing project info.
    /// @param _name The name of the ERC-20 token being create for the project.
    /// @param _symbol The symbol of the ERC-20 token being created for the project.
    /// @param _data The data needed to deploy a basic retailist project.
    /// @param _delegateAllocations Any pay delegate allocations that should run when the project is paid.
    /// @return projectId The ID of the newly created Retailist project.
    function deployTiered721PayAllocatorProjectFor(
        address _operator,
        JBProjectMetadata memory _projectMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams calldata _data,
        JBPayDelegateAllocation3_1_1[] calldata _delegateAllocations,
        uint256 _metadata,
        JBDeployTiered721DelegateData calldata _deployTiered721DelegateData
    ) external returns (uint256 projectId) {
      // Get the project ID, optimistically knowing it will be one greater than the current count.
      projectId = directory.projects().count() + 1;

      // Deploy the delegate contract.
      IJBTiered721Delegate _delegate =
          delegateDeployer.deployDelegateFor(projectId, _deployTiered721DelegateData, directory);

      // Keep a reference to the number of delegate allocations passed in.  
      uint256 _numberOfDelegateAllocations = _delegateAllocations.length; 

      // Track an updated list of delegate allocations that'll also fit the Tiered 721 Delegate allocation.
      JBPayDelegateAllocation3_1_1[] memory _updatedDelegateAllocations =  new JBPayDelegateAllocation3_1_1[](_numberOfDelegateAllocations + 1);
  
      // Repopulate the updated list with the params passed in.
      for (uint256 _i; _i < _numberOfDelegateAllocations;) {
        _updatedDelegateAllocations[_i] = _delegateAllocations[_i];
        unchecked {
          ++_i;
        }
      }

      // Add the Tiered 721 Allocation at the end.
      _updatedDelegateAllocations[_numberOfDelegateAllocations] = JBPayDelegateAllocation3_1_1({
        delegate: IJBPayDelegate3_1_1(address(_delegate)),
        amount: 0,
        metadata: bytes('') 
      });

      return super.deployPayAllocatorProjectFor(
        _operator,
        _projectMetadata,
        _name,
        _symbol,
        _data,
        _updatedDelegateAllocations,
        _metadata
      );
    }
}
