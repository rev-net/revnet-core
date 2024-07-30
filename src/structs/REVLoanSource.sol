// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member token The token that is being loaned.
/// @custom:member terminal The terminal that the loan is being made from.
struct REVLoanSource {
    address token;
    IJBPaymentTerminal terminal;
}
