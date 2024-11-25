// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member chainId The ID of the chain on which the mint should be honored.
/// @custom:member count The number of tokens that should be minted.
/// @custom:member beneficiary The address that will receive the minted tokens.
struct REVAutoIssuance {
    uint32 chainId;
    uint104 count;
    address beneficiary;
}
