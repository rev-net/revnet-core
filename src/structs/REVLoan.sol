// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVLoanSource} from "./REVLoanSource.sol";

/// @custom:member revnetId The ID of the revnet that this loan is for.
/// @custom:member borrowedAmount The amount that is being borrowed.
/// @custom:member collateralTokenCount The number of collateral tokens currently accounted for.
/// @custom:member loanedAt The timestamp when the loan was created.
/// @custom:member lastUpdated The timestamp when the loan was last updated.
/// @custom:member The source of the loan.
struct REVLoan {
    uint56 revnetId;
    uint112 amount;
    uint112 collateral;
    uint40 createdAt;
    REVLoanSource source;
}
