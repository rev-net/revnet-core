// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member name The name of the ERC-20 token being create for the revnet.
/// @custom:member symbol The symbol of the ERC-20 token being created for the revnet.
/// @custom:member uri The metadata URI containing revnet's info.
struct REVDescription {
    string name;
    string symbol;
    string uri;
}
