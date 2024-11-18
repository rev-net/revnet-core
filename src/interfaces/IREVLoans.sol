// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBTokenUriResolver} from "@bananapus/core/src/interfaces/IJBTokenUriResolver.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBSingleAllowance} from "@bananapus/core/src/structs/JBSingleAllowance.sol";

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
    event Liquidate(uint256 indexed loanId, uint256 indexed revnetId, REVLoan loan, address caller);
    event RepayLoan(
        uint256 indexed loanId,
        uint256 indexed revnetId,
        uint256 indexed paidOffLoanId,
        REVLoan loan,
        REVLoan paidOffLoan,
        uint256 amount,
        uint256 sourceFeeAmount,
        uint256 collateralToReturn,
        address payable beneficiary,
        address caller
    );
    event ReallocateCollateral(
        uint256 indexed loanId,
        uint256 indexed revnetId,
        uint256 indexed reallocatedLoanId,
        REVLoan reallocatedLoan,
        uint256 removedCollateral,
        address caller
    );
    event SetTokenUriResolver(IJBTokenUriResolver indexed resolver, address caller);

    function LOAN_LIQUIDATION_DURATION() external view returns (uint256);
    function MAX_PREPAID_FEE_PERCENT() external view returns (uint256);
    function PERMIT2() external view returns (IPermit2);
    function PROJECTS() external view returns (IJBProjects);
    function REV_ID() external view returns (uint256);
    function REV_PREPAID_FEE_PERCENT() external view returns (uint256);
    function SOURCE_MIN_PREPAID_FEE_PERCENT() external view returns (uint256);

    function borrowableAmountFrom(
        uint256 revnetId,
        uint256 collateral,
        uint256 decimals,
        uint256 currency
    )
        external
        view
        returns (uint256);
    function determineSourceFeeAmount(
        REVLoan memory loan,
        uint256 amount
    )
        external
        view
        returns (uint256 sourceFeeAmount);
    function isLoanSourceOf(uint256 revnetId, IJBPayoutTerminal terminal, address token) external view returns (bool);
    function loanOf(uint256 loanId) external view returns (REVLoan memory);
    function loanSourcesOf(uint256 revnetId) external view returns (REVLoanSource[] memory);
    function numberOfLoansFor(uint256 revnetId) external view returns (uint256);
    function revnetIdOfLoanWith(uint256 loanId) external view returns (uint256);
    function tokenUriResolver() external view returns (IJBTokenUriResolver);
    function totalBorrowedFrom(
        uint256 revnetId,
        IJBPayoutTerminal terminal,
        address token
    )
        external
        view
        returns (uint256);
    function totalCollateralOf(uint256 revnetId) external view returns (uint256);

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
    function liquidateExpiredLoansFrom(uint256 revnetId, uint256 startingLoanId, uint256 count) external;
    function repayLoan(
        uint256 loanId,
        uint256 newAmount,
        uint256 newCollateral,
        address payable beneficiary,
        JBSingleAllowance calldata allowance
    )
        external
        payable
        returns (uint256 paidOffLoanId, REVLoan memory loan);
    function reallocateCollateralFromLoan(
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
        returns (uint256 reallocatedLoanId, uint256 newLoanId, REVLoan memory reallocatedLoan, REVLoan memory newLoan);
    function setTokenUriResolver(IJBTokenUriResolver resolver) external;
}
