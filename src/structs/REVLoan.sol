// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {REVLoanSource} from "./REVLoanSource.sol";

/// @custom:member borrowedAmount The amount that is being borrowed.
/// @custom:member collateralTokenCount The number of collateral tokens currently accounted for.
/// @custom:member createdAt The timestamp when the loan was created.
/// @custom:member prepaidFeePercent The percentage of the loan's fees that were prepaid.
/// @custom:member prepaidDuration The duration that the loan was prepaid for.
/// @custom:member source The source of the loan.
struct REVLoan {
    uint112 amount;
    uint112 collateral;
    uint40 createdAt;
    uint16 prepaidFeePercent;
    uint32 prepaidDuration;
    REVLoanSource source;
}
