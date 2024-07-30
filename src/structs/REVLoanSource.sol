// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";

/// @custom:member token The token that is being loaned.
/// @custom:member terminal The terminal that the loan is being made from.
struct REVLoanSource {
    address token;
    IJBPayoutTerminal terminal;
}
