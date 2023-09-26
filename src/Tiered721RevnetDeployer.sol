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
import {
    BuybackHookSetupData,
    RevnetParams,
    PayHookRevnetDeployer
} from "./PayHookRevnetDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s.
contract Tiered721RevnetDeployer is PayHookRevnetDeployer {
    /// @notice The directory of terminals and controllers for revnets.
    IJBDirectory public immutable directory;

    /// @notice The contract responsible for deploying the tiered 721 hook.
    IJBTiered721DelegateDeployer public immutable tiered721HookDeployer;

    /// @param _directory The directory of terminals and controllers for revnets.
    /// @param _tiered721HookDeployer The tiered 721 hook deployer.
    /// @param _controller The controller that revnets are made from.
    constructor(
        IJBDirectory _directory,
        IJBTiered721DelegateDeployer _tiered721HookDeployer,
        IJBController3_1 _controller
    )
        PayHookRevnetDeployer(_controller)
    {
        directory = _directory;
        tiered721HookDeployer = _tiered721HookDeployer;
    }

    /// @notice Deploy a basic revnet that includes Tiered 721s and also calls other specified pay hooks.
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
    /// @return revnetId The ID of the newly created revnet.    
    function deployTiered721RevnetFor(
        address _boostOperator,
        JBProjectMetadata memory _revnetMetadata,
        string memory _name,
        string memory _symbol,
        RevnetParams memory _revnetData,
        IJBPaymentTerminal[] memory _terminals,
        BuybackHookSetupData memory _buybackHookSetupData,
        JBDeployTiered721DelegateData memory _tiered721SetupData,
        JBPayDelegateAllocation3_1_1[] memory _otherPayHooks,
        uint8 _extraCycleMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Get the revnet ID, optimistically knowing it will be one greater than the current count.
        revnetId = directory.projects().count() + 1;

        // Keep a reference to the number of pay hooks passed in.
        uint256 _numberOfOtherPayHooks = _otherPayHooks.length;

        // Track an updated list of pay hooks that'll also fit the tiered 721 hook.
        JBPayDelegateAllocation3_1_1[] memory _payHooks =
            new JBPayDelegateAllocation3_1_1[](_numberOfOtherPayHooks + 1);

        // Repopulate the updated list with the params passed in.
        for (uint256 _i; _i < _numberOfOtherPayHooks;) {
            _payHooks[_i] = _otherPayHooks[_i];
            unchecked {
                ++_i;
            }
        }

        // Deploy the tiered 721 hook contract.
        IJBTiered721Delegate _tiered721Hook = tiered721HookDeployer.deployDelegateFor(revnetId, _tiered721SetupData);

        // Add the tiered 721 hook at the end.
        _payHooks[_numberOfOtherPayHooks] = JBPayDelegateAllocation3_1_1({
            delegate: IJBPayDelegate3_1_1(address(_tiered721Hook)),
            amount: 0,
            metadata: bytes("")
        });

        super.deployPayHookNetworkFor(
            _boostOperator,
            _revnetMetadata,
            _name,
            _symbol,
            _revnetData,
            _terminals,
            _buybackHookSetupData,
            _payHooks,
            _extraCycleMetadata
        );
    }
}
