// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IJBController} from "@juice/interfaces/IJBController.sol";
import {IJBPermissioned} from "@juice/interfaces/IJBPermissioned.sol";
import {IJBRulesetDataHook} from "@juice/interfaces/IJBRulesetDataHook.sol";
import {JBPermissionIds} from "@juice/libraries/JBPermissionIds.sol";
import {JBRedeemParamsData} from "@juice/structs/JBRedeemParamsData.sol";
import {JBPayParamsData} from "@juice/structs/JBPayParamsData.sol";
import {JBRedeemHookPayload} from "@juice/structs/JBRedeemHookPayload.sol";
import {JBPayHookPayload} from "@juice/structs/JBPayHookPayload.sol";
import {JBRulesetConfig} from "@juice/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "@juice/structs/JBTerminalConfig.sol";
import {JBPermissionsData} from "@juice/structs/JBPermissionsData.sol";
import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {REVDeployParams} from "./structs/REVDeployParams.sol";
import {REVBuybackHookSetupData} from "./structs/REVBuybackHookSetupData.sol";
import {REVBasicDeployer} from "./REVBasicDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
contract REVPayHookDeployer is REVBasicDeployer, IJBRulesetDataHook {
    /// @notice The data hook that returns the correct values for the buyback hook of each network.
    /// @custom:param revnetId The ID of the revnet to which the buyback contract applies.
    mapping(uint256 revnetId => IJBBuybackHook buybackHook) public buybackHookOf;

    /// @notice The pay hooks to include during payments to networks.
    /// @custom:param revnetId The ID of the revnet to which the extensions apply.
    mapping(uint256 revnetId => JBPayHookPayload[] payHooks) public _payHooksOf;

    /// @notice The permissions that the provided buyback hook should be granted since it wont be used as the data
    /// source.
    /// This is set once in the constructor to contain only the MINT operation.
    uint256[] private _BUYBACK_HOOK_PERMISSION_IDS;

    /// @notice The pay hooks to include during payments to networks.
    /// @param revnetId The ID of the revnet to which the extensions apply.
    /// @return payHook The pay hooks.
    function payHooksOf(uint256 revnetId) external view returns (JBPayHookPayload[] memory) {
        return _payHooksOf[revnetId];
    }

    /// @notice This function gets called when the revnet receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param data The Juicebox standard network payment data. See
    /// https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that network tokens should get minted relative to. This is useful for optionally
    /// customizing how many tokens are issued per payment.
    /// @return payHooks Amount to be sent to pay hooks instead of adding to local balance. Useful for
    /// auto-routing funds from a treasury as payment come in.
    function payParams(JBPayParamsData calldata data)
        external
        view
        virtual
        override
        returns (uint256 weight, JBPayHookPayload[] memory payHooks)
    {
        // Keep a reference to the hooks that the buyback hook data source provides.
        JBPayHookPayload[] memory buybackHooks;

        // // Set the values to be those returned by the buyback hook's data source.
        (weight, buybackHooks) = buybackHookOf[data.projectId].payParams(data);

        // Check if a buyback hook is used.
        bool usesBuybackHook = buybackHooks.length != 0;

        // Cache any other pay hooks to use.
        JBPayHookPayload[] memory storedPayHooks = _payHooksOf[data.projectId];

        // Keep a reference to the number of pay hooks;
        uint256 numberOfStoredPayHooks = storedPayHooks.length;

        // Each delegate allocation must run, plus the buyback hook if provided.
        payHooks = new JBPayHookPayload[](numberOfStoredPayHooks + (usesBuybackHook ? 1 : 0));

        // Add the other expected pay hooks.
        for (uint256 i; i < numberOfStoredPayHooks; i++) {
            payHooks[i] = storedPayHooks[i];
        }

        // Add the buyback hook as the last element.
        if (usesBuybackHook) payHooks[numberOfStoredPayHooks] = buybackHooks[0];
    }

    /// @notice This function is never called, it needs to be included to adhere to the interface.
    function redeemParams(JBRedeemParamsData calldata data)
        external
        view
        virtual
        override
        returns (uint256, JBRedeemHookPayload[] memory payloads)
    {
        data; // Unused.
        return (0, payloads);
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(REVBasicDeployer, IERC165)
        returns (bool)
    {
        return interfaceId == type(IJBRulesetDataHook).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @param controller The controller that revnets are made from.
    constructor(IJBController controller) REVBasicDeployer(controller) {
        _BOOST_OPERATOR_PERMISSIONS_INDEXES.push(JBPermissionIds.MINT_TOKENS);
    }

    /// @notice Deploy a basic revnet that also calls other specified pay hooks.
    /// @param boostOperator The address that will receive the token premint and initial boost, and who is
    /// allowed to change the boost recipients. Only the boost operator can replace itself after deployment.
    /// @param revnetMetadata The metadata containing revnet's info.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param deployData The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookSetupData Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param payHooks Any hooks that should run when the revnet is paid.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    function deployPayHookNetworkFor(
        address boostOperator,
        string memory revnetMetadata,
        string memory name,
        string memory symbol,
        REVDeployParams memory deployData,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookSetupData memory buybackHookSetupData,
        JBPayHookPayload[] memory payHooks,
        uint8 extraHookMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet
        revnetId =
         _deployRevnetFor({
            boostOperator: boostOperator,
            revnetMetadata: revnetMetadata,
            name: name,
            symbol: symbol,
            deployData: deployData,
            terminalConfigurations: terminalConfigurations,
            buybackHookSetupData: buybackHookSetupData,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: extraHookMetadata
        });

        // Give the buyback hook permission to mint on this contract's behald if it doesn't yet have it.
        if (
            !IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().hasPermissions({
                operator: address(buybackHookSetupData.hook),
                account: address(this),
                projectId: 0,
                permissionIds: _BUYBACK_HOOK_PERMISSION_IDS
            })
        ) {
            IJBPermissioned(address(CONTROLLER.SPLITS())).PERMISSIONS().setPermissionsFor({
                account: address(this),
                permissionsData: JBPermissionsData({
                    operator: address(buybackHookSetupData.hook),
                    projectId: 0,
                    permissionIds: _BUYBACK_HOOK_PERMISSION_IDS
                })
            });
        }

        // Store the pay hooks.
        _storeHooksOf(revnetId, payHooks);
    }

    /// @notice Stores pay hooks for the provided revnet.
    /// @param revnetId The ID of the revnet to which the pay hooks apply.
    /// @param payHooks The pay hooks to store.
    function _storeHooksOf(uint256 revnetId, JBPayHookPayload[] memory payHooks) internal {
        // Keep a reference to the number of pay hooks are being stored.
        uint256 numberOfPayHooks = payHooks.length;

        // Store the pay hooks.
        for (uint256 i; i < numberOfPayHooks; i++) {
            _payHooksOf[revnetId][i] = payHooks[i];
        }
    }
}
