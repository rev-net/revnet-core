// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBTokenUriResolver} from "@bananapus/core/src/interfaces/IJBTokenUriResolver.sol";
import {JBSingleAllowance} from "@bananapus/core/src/structs/JBSingleAllowance.sol";

import {IREVDeployer} from "./IREVDeployer.sol";
import {REVLoan} from "./../structs/REVLoan.sol";
import {REVLoanSource} from "./../structs/REVLoanSource.sol";

interface IREVLoans {
    event Borrow(
        uint256 indexed loanId,
        uint256 indexed revnetId,
        REVLoan loan,
        REVLoanSource source,
        uint256 borrowAmount,
        uint256 collateralCount,
        uint256 sourceFeeAmount,
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
        uint256 repayBorrowAmount,
        uint256 sourceFeeAmount,
        uint256 collateralCountToReturn,
        address payable beneficiary,
        address caller
    );
    event ReallocateCollateral(
        uint256 indexed loanId,
        uint256 indexed revnetId,
        uint256 indexed reallocatedLoanId,
        REVLoan reallocatedLoan,
        uint256 removedcollateralCount,
        address caller
    );
    event SetTokenUriResolver(IJBTokenUriResolver indexed resolver, address caller);

    function LOAN_LIQUIDATION_DURATION() external view returns (uint256);
    function PERMIT2() external view returns (IPermit2);
    function CONTROLLER() external view returns (IJBController);
    function REVNETS() external view returns (IREVDeployer);
    function DIRECTORY() external view returns (IJBDirectory);
    function PRICES() external view returns (IJBPrices);
    function PROJECTS() external view returns (IJBProjects);
    function REV_ID() external view returns (uint256);
    function REV_PREPAID_FEE_PERCENT() external view returns (uint256);
    function MIN_PREPAID_FEE_PERCENT() external view returns (uint256);
    function MAX_PREPAID_FEE_PERCENT() external view returns (uint256);

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
        uint256 minBorrowAmount,
        uint256 collateral,
        address payable beneficiary,
        uint256 prepaidFeePercent
    )
        external
        returns (uint256 loanId, REVLoan memory loan);
    function liquidateExpiredLoansFrom(uint256 revnetId, uint256 startingLoanId, uint256 count) external;
    function repayLoan(
        uint256 loanId,
        uint256 maxRepayBorrowAmount,
        uint256 collateralCountToReturn,
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
        uint256 minBorrowAmount,
        uint256 collateralToAdd,
        address payable beneficiary,
        uint256 prepaidFeePercent
    )
        external
        payable
        returns (uint256 reallocatedLoanId, uint256 newLoanId, REVLoan memory reallocatedLoan, REVLoan memory newLoan);
    function setTokenUriResolver(IJBTokenUriResolver resolver) external;
}
