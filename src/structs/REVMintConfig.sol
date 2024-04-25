// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member chainId The ID of the chain on which the mint should be honored.
/// @custom:member count The number of tokens that should be minted.
/// @custom:member beneficiary The address that will receive the minted tokens.
struct REVMintConfig {
    uint256 chainId;
    uint256 count;
    address beneficiary;
}
