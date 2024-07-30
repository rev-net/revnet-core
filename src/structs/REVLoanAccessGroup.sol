// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member terminal The terminal that the loan applies to.
/// @custom:member token The token that the loan applies to within the `terminal`.
struct REVLoanAccessGroup {
    address terminal;
    address token;
}
