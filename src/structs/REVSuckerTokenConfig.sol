// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct REVSuckerTokenConfig {
    address localToken;
    address remoteToken;
    uint32 minGas;
    uint256 minBridgeAmount;
}
