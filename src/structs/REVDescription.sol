// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member name The name of the ERC-20 token being create for the revnet.
/// @custom:member ticker The ticker of the ERC-20 token being created for the revnet.
/// @custom:member uri The metadata URI containing revnet's info.
/// @custom:member salt Revnets deployed across chains by the same address with the same salt will have the same
/// address.
struct REVDescription {
    string name;
    string ticker;
    string uri;
    bytes32 salt;
}
