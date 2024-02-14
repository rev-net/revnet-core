pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {REVBuybackHookConfig} from "../structs/REVBuybackHookConfig.sol";
import {REVConfig} from "../structs/REVConfig.sol";

interface IREVBasicDeployer {
    function deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        SuckerTokenConfig[] memory suckerTokenConfig,
        bytes32 suckerSalt
    )
        external
        returns (uint256 revnetId);
}

interface BPSuckerDeployer {
    function createForSender(
        uint256 localProjectId,
        bytes32 salt
    ) external returns (address);
}

struct SuckerTokenConfig {
    address localToken;
    address remoteToken;
    uint32 minGas;
    uint256 minBridgeAmount;
}

struct BPTokenConfig {
    uint32 minGas;
    address remoteToken;
    uint256 minBridgeAmount;
}

interface BPSucker {
    function configureToken(address token, BPTokenConfig calldata config) external;
}