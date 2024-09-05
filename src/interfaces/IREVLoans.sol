// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {JBSingleAllowance} from "@bananapus/core/src/structs/JBSingleAllowance.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {REVLoan} from "./../structs/REVLoan.sol";
import {REVLoanSource} from "./../structs/REVLoanSource.sol";

interface IREVLoans {
    event Borrow(
        uint256 indexed loanId,
        uint256 indexed revnetId,
        REVLoan loan,
        REVLoanSource source,
        uint256 amount,
        uint256 collateral,
        address payable beneficiary,
        address caller
    );
    event PayOff(
        uint256 indexed loanId,
        uint256 indexed paidOffLoanId,
        REVLoan loan,
        REVLoan paidOffLoan,
        uint256 amount,
        uint256 sourceFeeAmount,
        uint256 collateralToReturn,
        address payable beneficiary,
        address caller
    );
    event Refinance(
        uint256 indexed loanId,
        uint256 indexed refinancedLoanId,
        uint256 indexed revnetId,
        REVLoan refinancedLoan,
        uint256 removedCollateral,
        address caller
    );
    event Liquidate(uint256 indexed loanId, uint256 indexed revnetId, REVLoan loan, address caller);

    function REV_PREPAID_FEE() external view returns (uint256);
    function MAX_PREPAID_PERCENT() external view returns (uint256);
    function LOAN_LIQUIDATION_DURATION() external view returns (uint256);
    function PROJECTS() external view returns (IJBProjects);
    function REV_ID() external view returns (uint256);
    function PERMIT2() external view returns (IPermit2);

    function numberOfLoansFor(uint256 revnetId) external view returns (uint256);
    function lastLoanIdLiquidatedFrom(uint256 revnetId) external view returns (uint256);
    function isLoanSourceOf(uint256 revnetId, IJBPayoutTerminal terminal, address token) external view returns (bool);
    function loanSourcesOf(uint256 revnetId) external view returns (REVLoanSource[] memory);
    function loanOf(uint256 loanId) external view returns (REVLoan memory);
    function borrowableAmountFrom(
        uint256 revnetId,
        uint256 collateral,
        uint256 decimals,
        uint256 currency
    )
        external
        view
        returns (uint256);
    function totalBorrowedFrom(
        uint256 revnetId,
        IJBPayoutTerminal terminal,
        address token
    )
        external
        view
        returns (uint256);
    function totalCollateralOf(uint256 revnetId) external view returns (uint256);
    function revnetIdOfLoanWithId(uint256 loanId) external view returns (uint256);

    function borrowFrom(
        uint256 revnetId,
        REVLoanSource calldata source,
        uint256 amount,
        uint256 collateral,
        address payable beneficiary,
        uint256 prepaidFeePercent
    )
        external
        returns (uint256 loanId, REVLoan memory loan);
    function refinanceLoan(
        uint256 loanId,
        uint256 collateralToTransfer,
        REVLoanSource calldata source,
        uint256 amount,
        uint256 collateralToAdd,
        address payable beneficiary,
        uint256 prepaidFeePercent
    )
        external
        payable
        returns (uint256 refinancedLoanId, uint256 newLoanId, REVLoan memory refinancedLoan, REVLoan memory newLoan);

    function payOff(
        uint256 loanId,
        uint256 newAmount,
        uint256 newCollateral,
        address payable beneficiary,
        JBSingleAllowance calldata allowance
    )
        external
        payable
        returns (uint256 paidOffLoanId, REVLoan memory loan);

    function liquidateExpiredLoansFrom(uint256 revnetId, uint256 count) external;
}
