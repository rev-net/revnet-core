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
        IJBPayoutTerminal terminal,
        address token,
        uint256 amount,
        uint256 collateral,
        address payable beneficiary,
        address caller
    );
    event Refinance(
        uint256 indexed loanId,
        uint256 indexed newLoanId,
        REVLoan loan,
        IJBPayoutTerminal terminal,
        address token,
        uint256 amount,
        uint256 collateral,
        address payable beneficiary,
        address caller
    );
    event Liquidate(uint256 indexed loanId, REVLoan loan, address caller);

    function REV_PREPAID_FEE() external view returns (uint256);
    function SELF_PREPAID_FEE() external view returns (uint256);
    function LOAN_PREPAID_DURATION() external view returns (uint256);
    function LOAN_LIQUIDATION_DURATION() external view returns (uint256);
    function PROJECTS() external view returns (IJBProjects);
    function FEE_REVNET_ID() external view returns (uint256);
    function PERMIT2() external view returns (IPermit2);
    function numberOfLoans() external view returns (uint256);
    function lastLoanIdLiquidated() external view returns (uint256);

    function isLoanSourceOf(uint256 revnetId, IJBPayoutTerminal terminal, address token) external view returns (bool);
    function loanSourcesOf(uint256 revnetId) external view returns (REVLoanSource[] memory);
    function loanOf(uint256 loanId) external view returns (REVLoan memory);
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
        IJBPayoutTerminal terminal,
        address token,
        uint256 amount,
        uint256 collateral,
        address payable beneficiary
    )
        external
        returns (uint256 loanId);

    function refinance(
        uint256 loanId,
        uint256 newAmount,
        uint256 newCollateral,
        address payable beneficiary,
        JBSingleAllowance memory allowance
    )
        external
        payable
        returns (uint256 newLoanId);

    function liquidateExpiredLoans(uint256 count) external;
}
