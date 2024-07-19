// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Criteria for allowed posts.
/// @custom:member category A category that should allow posts.
/// @custom:member minimumPrice The minimum price that a post to the specified category should cost.
/// @custom:member minimumTotalSupply The minimum total supply of NFTs that can be made available when minting.
/// @custom:member maxTotalSupply The max total supply of NFTs that can be made available when minting. Leave as 0 for
/// max.
/// @custom:member allowedAddresses A list of addresses that are allowed to post on the category through Croptop.
struct REVCroptopAllowedPost {
    uint24 category;
    uint104 minimumPrice;
    uint32 minimumTotalSupply;
    uint32 maximumTotalSupply;
    address[] allowedAddresses;
}
