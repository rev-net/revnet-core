// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBTerminalStore} from "@bananapus/core/src/interfaces/IJBTerminalStore.sol";
import {JBSurplus} from "@bananapus/core/src/libraries/JBSurplus.sol";
import {IREVLoans} from "./interfaces/IREVLoans.sol";
import {JBRedemptions} from "@bananapus/core/src/libraries/JBRedemptions.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";

import {REVLoan} from "./structs/REVLoan.sol";
import {REVLoanSource} from "./structs/REVLoanSource.sol";

/// @notice A contract for borrowing from revnets.
contract REVLoans is IREVLoans {
    error MISSING_VALUES();
    error NOT_ENOUGH_COLLATERAL();
    error PERMIT_ALLOWANCE_NOT_ENOUGH();
    error NO_MSG_VALUE_ALLOWED();

    /// @dev A fee of 10% is charged at the time a loan is created. 2.5% is charged by the underlying protocol, 2.5% is
    /// charged by REV, 5% is charge by the revnet issuing the loan.
    uint256 public constant override REV_PREPAID_FEE = 25; // 2.5%

    /// @dev The initial fee taken by the revnet issuing the loan.
    uint256 public constant override SELF_PREPAID_FEE = 50; // 5%

    /// @dev The initial fee covers the loan for 2 years. The loan can be repaid at anytime within this time frame for
    /// no additional charge.
    uint256 public constant override LOAN_PREPAID_DURATION = 2 years;

    /// @dev After 2 years, the loan will increasingly cost more to pay off. After 10 years, the loan collateral cannot
    /// be recouped.
    uint256 public constant override LOAN_LIQUIDATION_DURATION = 10 years;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable override PROJECTS;

    /// @notice The ID of the REV revnet that will receive the fees.
    uint256 public immutable override FEE_REVNET_ID;

    /// @notice The amount of loans that have been created.
    uint256 public numberOfLoans;

    /// @notice The ID of the last revnet that has been successfully liquiditated after passing the duration.
    uint256 public lastLoanIdLiquidated;

    /// @notice An indication if a revnet currently has outstanding loans from the specified terminal in the specified
    /// token.
    /// @custom:member revnetId The ID of the revnet issuing the loan.
    /// @custom:member terminal The terminal that the loan is issued from.
    /// @custom:member token The token being loaned.
    mapping(uint256 revnetId => mapping(IJBTerminal terminal => mapping(address token => bool))) public isLoanSourceOf;

    /// @notice The sources of each revnet's loan.
    /// @custom:member revnetId The ID of the revnet issuing the loan.
    mapping(uint256 revnetId => REVLoanSource[]) public loanSourcesOf;

    /// @notice The loans.
    /// @custom:member The ID of the loan.
    mapping(uint256 loanId => REVLoan) loanOf;

    /// @notice The total amount loaned out by a revnet from a specified terminal in a specified token.
    /// @custom:member revnetId The ID of the revnet issuing the loan.
    /// @custom:member terminal The terminal that the loan is issued from.
    /// @custom:member token The token being loaned.
    mapping(uint256 revnetId => mapping(IJBTerminal terminal => mapping(address token => uint256))) totalBorrowedFrom;

    /// @notice The total amount of collateral supporting a revnet's loans.
    /// @custom:member revnetId The ID of the revnet issuing the loan.
    mapping(uint256 revnetId => uint256) totalCollateralOf;

    /// @notice Checks this contract's balance of a specific token.
    /// @param token The address of the token to get this contract's balance of.
    /// @return This contract's balance.
    function _balanceOf(address token) internal view returns (uint256) {
        // If the `token` is native, get the native token balance.
        return token == JBConstants.NATIVE_TOKEN ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /// @param projects A contract which mints ERC-721s that represent project ownership and transfers.
    /// @param feeRevnetId The ID of the REV revnet that will receive the fees.
    constructor(IJBProjects projects, uint256 feeRevnetId) {
        PROJECTS = projects;
        FEE_REVNET_ID = feeRevnetId;
    }

    /// @notice Open a loan by borrowing from a revnet.
    /// @param revnetId The ID of the revnet being borrowed from.
    /// @param terminal The terminal where the funds will be borrowed from.
    /// @param token The token being borrowed.
    /// @param amount The amount being borrowed.
    /// @param collateralTokenCount The amount of tokens to use as collateral for the loan.
    /// @param beneficiary The address that'll receive the borrowed funds and the tokens resulting from fee payments.
    /// @return loanedAmount The amount being loaned out after all prepaid fees are taken.
    function borrowFrom(
        uint256 revnetId,
        IJBPayoutTerminal terminal,
        address token,
        uint256 amount,
        uint256 collateral,
        address beneficiary
    )
        external
        view
        returns (uint256 loanId, uint256 netNewBorrowedAmount)
    {
        // Make sure there is an amount being borrowed.
        if (amount == 0) revert MISSING_VALUES();

        // Get a reference to the loan ID.
        loanId = ++numberOfLoans;

        // Mint the loan.
        _mint({to: msg.sender, tokenId: loanId});

        // Get a reference to the loan being created.
        REVLoan storage loan = loanOf[loanId];

        // Set the loan's values.
        loan.revnetId = revnetId;
        loan.source = REVLoanSource({terminal: terminal, token: token});
        loan.createdAt = block.timestamp;

        // Make an empty allowance to satisfy the function.
        JBSingleAllowance memory allowance;

        // Borrow the amount.
        netNewBorrowedAmount = _refinance({
            loan: loan,
            totalAmount: amount,
            totalCollateral: collateral,
            beneficiary: beneficiary,
            allowance: allowance
        });
    }

    /// @notice Allows the owner of a loan to pay it back, add more, or receive returned collateral no longer necessary
    /// to support the loan.
    /// @param loanId The ID of the loan being managed.
    /// @param amountToPayBack The amount being paid back.
    /// @param amountOfCollateralToReturn The amount of collateral to returned.
    /// @param beneficiary The address receiving the returned collateral.
    /// @param allowance An allowance to faciliate permit2 interactions.
    /// @return amountPaidBack The amount paid back to the loan's owner.
    /// @return amountOfCollateralToReturn The amount of collateral returned to the loan's owner.
    function refinance(
        uint256 memory loanId,
        uint256 newAmount,
        uint256 newCollateral,
        address beneficiary,
        JBSingleAllowance memory allowance
    )
        external
        payable
        returns (uint256 netNewBorrowedAmount)
    {
        // Make sure only the loan's owner can manage it.
        if (_ownerOf(loanId) != msg.sender) revert UNAUTHORIZED();

        // Keep a reference to the fee being iterated on.
        REVLoan storage loan = loanOf[loanId];

        // Borrow in.
        netNewBorrowedAmount = _refinance({
            loan: loan,
            totalAmount: newAmount,
            totalCollateral: newCollateral,
            beneficiary: beneficiary,
            allowance: allowance
        });

        if (loan.amount == 0 && loan.collateral == 0) {
            // Burn the loan.
            _burn(loanId);
        }
    }

    function _refinance(
        REVLoan storage loan,
        uint256 newAmount,
        uint256 newCollateral,
        address beneficiary,
        JBSingleAllowance memory allowance
    )
        internal
        returns (uint256 netNewBorrowedAmount)
    {
        // Keep a reference to the revnet's owner.
        IREVBasic revnetOwner = IREVBasic(PROJECTS.ownerOf(loan.revnetId));

        // Keep a reference to the revnet's controller.
        IJBController controller = revnetOwner.CONTROLLER();

        // Keep a reference to the revnet's directory.
        IJBController directory = controller.DIRECTORY();

        // If the borrowed amount is increasing or the collateral is changing, check that the loan will still be
        // properly collateralized.
        if (newAmount > loan.amount || loan.collateral != newCollateral) {
            // Get the surplus of all the revnet's terminals in terms of the native currency.
            uint256 totalSurplus = JBSurplus.currentSurplusOf({
                projectId: loan.revnetId,
                terminals: directory.terminalsOf(loan.revnetId),
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            });

            // Get the revnet's current stage.
            JBRuleset memory currentStage = controller.RULESETS().currentOf(loan.revnetId);

            // Get the total amount the revnet currently has loaned out, in terms of the native currency with 18
            // decimals.
            uint256 totalBorrowed = _totalBorrowedFrom({
                revnetId: loan.revnetId,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            });

            // Get the total amount of tokens in circulation.
            uint256 totalSupply = controller.TOKENS().totalSupplyOf(loan.revnetId);

            // Get a refeerence to the collateral being used to secure loans.
            uint256 totalCollateral = totalCollateralOf[loan.revnetId];

            // Get the amount that cashing out would return given a surplus that includes all loaned out tokens. This
            // becomes the amount of the loan.
            uint256 borrowableAmount = JBRedemptions.reclaimFrom({
                surplus: totalSurplus + totalBorrowed,
                tokensRedeemed: newCollateral,
                totalSupply: totalSupply + totalCollateral,
                redemptionRate: currentStage.redemptionRate()
            });

            // Make sure the amount being loaned is within the allowed amount.
            if (newAmount > borrowableAmount) revert NOT_ENOUGH_COLLATERAL();
        }

        // Add to the loan.
        if (newAmount > loan.amount) {
            // Register the source if this is the first time its being used for this revnet.
            if (!isLoanSourceOf[revnetId][terminal][token]) {
                isLoanSourceOf[revnetId][terminal][token] = true;
                loanSourcesOf[revnetId].push(REVLoanSource({token: token, terminal: terminal}));
            }

            // Keep a reference to the difference in amounts, which is the amount being borrowed.
            uint256 amountDiff = newAmount - loan.amount;

            // Increment the amount of the token borrowed from the revnet from the terminal.
            totalBorrowedFrom[revnetId][terminal][token] += amountDiff;

            // Get a reference to the accounting context for the source.
            JBAccountingContext memory accountingContext =
                source.terminal.accountingContextForTokenOf({projectId: revnetId, token: source.token});

            // Pull the amount to be loaned out of the revnet. This will incure the protocol fee.
            terminal.useAllowanceOf({
                projectId: loan.revnetId,
                token: loan.source.token,
                amount: amountDiff,
                currency: accountingContext.currency,
                minTokensPaidOut: amountDiff,
                beneficiary: address(this),
                memo: "Lending out to a borrower"
            });

            // Get the amount of additional fee to take for REV.
            uint256 feeAmount = mulDiv(amountDiff, REV_PREPAID_FEE, JBConstants.MAX_FEE);

            // Find the terminal that'll have the loaned amount added back to it.
            IJBTerminal feeTerminal = directory.primaryTerminalOf(FEE_REVNET_ID, token);

            // The amount to pay as a fee.
            uint256 payValue = token == JBConstants.NATIVE_TOKEN ? feeAmount : 0;

            // Pay the fee. Send the REV to the msg.sender.
            try feeTerminal.pay{value: payValue}({
                projectId: FEE_REVNET_ID,
                token: token,
                amount: feeAmount,
                beneficiary: beneficiary,
                minReturnedTokens: 0,
                memo: "Fee from loan",
                metadata: bytes(abi.encodePacked(revnetId))
            }) {} catch (bytes memory) {}

            // Get the amount of additional fee to take for the revnet issuing the loan.
            feeAmount = mulDiv(amountDiff, SELF_PREPAID_FEE, JBConstants.MAX_FEE);

            // The amount to pay as a fee.
            payValue = token == JBConstants.NATIVE_TOKEN ? feeAmount : 0;

            // Pay the fee. Add the tokens generated as collateral.
            try terminal.pay{value: payValue}({
                projectId: loan.revnetId,
                token: token,
                amount: feeAmount,
                beneficiary: address(this),
                minReturnedTokens: 0,
                memo: "Fee from loan",
                metadata: bytes(abi.encodePacked(FEE_REVNET_ID))
            }) returns (uint256 beneficiaryTokenAmount) {
                newCollateral += beneficiaryTokenAmount;
            } catch (bytes memory) {}

            // Transfer the remaining balance to the borrower.
            _transferFor({from: address(this), to: beneficiary, token: token, amount: _balanceOf(token)});

            // Pay off the loan.
        } else if (loan.amount > newAmount) {
            // Get a reference to the amount being paid back.
            uint256 amountDiff = loan.amount - newAmount;

            // Keep a reference to the time since the loan was created.
            uint256 timeSinceLoanCreated = block.timestamp - loan.loanedAt;

            // Keep a reference to the fee that'll be taken.
            uint256 feeAmount;

            // If the loan period has passed the prepaid time frame, take a fee.
            if (timeSinceLoanCreated > LOAN_PREPAID_DURATION) {
                // If the loan period has passed the liqidation time frame, do not allow loan management.
                if (timeSinceLoanCreate > LOAN_LIQUIDATION_TIMEFRAME) revert LOAN_EXPIRED();

                // Calculate the fee as a linear proportion given the amount of time that has passed.
                feeAmount = mulDiv(amountDiff, timeSinceLoanCreated, LOAN_LIQUIDATION_TIMEFRAME);
            }

            // Decrement the total amount of a token being loaned out by the revnet from its terminal.
            totalBorrowedFrom[revnetId][loan.terminal][loan.token] -= amountDiff;

            // Accept the funds that'll be used to pay off loans.
            uint256 amountPaidIn = _acceptFundsFor({
                projectId: loan.revnetId,
                token: loan.source.token,
                amount: amountDiff + feeAmount,
                allowance: allowance
            });

            // If the loan is being overpaid, transfer any leftover amount back to the payer.
            if (amountPaidIn > loan.amount + feeAmount) {
                _transferFor({
                    from: address(this),
                    to: msg.sender,
                    token: loan.source.token,
                    amount: amountPaidIn - loan.amount - feeAmount
                });
            }

            // The amount to pay as a fee.
            uint256 payValue = token == JBConstants.NATIVE_TOKEN ? feeAmount : 0;

            // Pay the fee.
            try loan.source.terminal.pay{value: payValue}({
                projectId: loan.revnetId,
                token: loan.source.token,
                amount: feeAmount,
                beneficiary: beneficiary,
                minReturnedTokens: 0,
                memo: "Fee from loan",
                metadata: bytes(abi.encodePacked(FEE_REVNET_ID))
            }) {} catch (bytes memory) {}

            // The borrowed amount to return to the revnet.
            uint256 payValue = token == JBConstants.NATIVE_TOKEN ? amountDiff : 0;

            // Add the loaned amount back to the revnet.
            try loan.source.terminal.addToBalance{value: payValue}({
                projectId: loan.revnetId,
                token: token,
                amount: amountDiff,
                shouldReturnHeldFees: false,
                memo: "Paying off loan",
                metadata: bytes(abi.encodePacked(revnetId))
            }) {} catch (bytes memory) {}
        }

        // Add more collateral.
        if (newCollateral > loan.collateral) {
            // Keep a reference to the new amount being used as collateral.
            uint256 collateralDiff = newCollateral - loan.collateral;

            // Increment the total amount of collateral tokens.
            totalCollateralOf[revnetId] += collateralDiff;

            // Burn the tokens that are tracked as collateral.
            controller.burnTokensOf({
                holder: msg.sender,
                projectId: revnetId,
                tokenCount: collateralDiff,
                memo: "Adding collateral to loan"
            });
            // Remove collateral.
        } else if (loan.collateral > newCollateral) {
            // Keep a reference to the amount of collateral being returned.
            uint256 collateralDiff = loan.collateral - newCollateral;

            // Decrement the total amount of collateral tokens.
            totalCollateralOf[revnetId] -= collateralDiff;

            // Mint the collateral tokens back to the loan payer.
            deployer.CONTROLLER().mintTokensOf({
                projectId: loan.revnetId,
                tokenCount: collateralDiff,
                beneficiary: beneficiary,
                memo: "Removing collateral from loan",
                useReservedPercent: false
            });
        }

        // Store the loans updated values.
        loan.amount = newAmount;
        loan.collateral = newCollateral;
    }

    /// @notice Cleans up any liquiditated loans.
    /// @dev Since loans are created in incremental order, earlier IDs will always be liquidated before later ones.
    /// @param count The amount of loans iterate over since the last liquidated loan.
    function liquidateExpiredLoans(uint256 count) external {
        // Keep a reference to the loan being iterated on.
        REVLoan memory loan;

        // Keep a reference to the number of loans liquiditated.
        uint256 numberOfLoansLiquidated;

        // Iterate over the desired number of loans to check for liquidation.
        for (uint256 i; i < count; i++) {
            // Get a reference to the loan being iterated on.
            loan = loanOf[lastCleaned + i];

            // If the the loan has passed its liquidation timeframe, liquidate it.
            if (block.timestamp - loan.loanedAt > LOAN_LIQUIDATION_TIMEFRAME) {
                // Decrement the amount loaned.
                totalBorrowedFrom[loan.revnetId][loan.terminal][loan.token] -= loan.borrowedAmount;

                // Decrement the total amount of collateral tokens supporting loans from this revnet.
                totalCollateralOf[loan.revnetId] -= loan.collateralTokenCount;

                // Burn the loan.
                _burn(loan.loanId);

                // Increment the number of loans liquidated.
                numberOfLoansLiquidated++;
            } else {
                // Store the latest liquidated loan.
                if (numberOfLoansLiquidated > 0) lastLoanIdLiquidated += numberOfLoansLiquidated;
                return;
            }
        }
    }

    /// @notice The total borrowed amount from a revnet.
    /// @param revnetId The ID of the revnet to check for borrowed assets from.
    /// @param decimals The decimals the resulting fixed point value will include.
    /// @param currency The currency the resulting value will be in terms of.
    /// @return borrowedAmount The total amount borrowed.
    function _totalBorrowedFrom(
        uint256 revnetId,
        uint256 decimals,
        uint256 currency
    )
        internal
        view
        returns (uint256 borrowedAmount)
    {
        // Keep a reference to all sources being used to loaned out from this revnet.
        REVLoanSources[] memory sources = loanSourcesOf[revnetId];

        // Keep a reference to the number of sources being loaned out.
        uint256 numberOfTokens = tokens.length;

        // Keep a reference to the source being iterated on.
        REVLoanSources memory source;

        // Iterate over all sources being used to loaned out.
        for (uint256 i = 0; i < numberOfSources; i++) {
            // Get a reference to the token being iterated on.
            source = sources[i];

            // Get a reference to the accounting context for the source.
            JBAccountingContext memory accountingContext =
                source.terminal.accountingContextForTokenOf({projectId: revnetId, token: source.token});

            // Normalize the price to the provided currency and decimals.
            uint256 pricePerUnit = accountingContext.currency == currency
                ? 10 ** decimals
                : PRICES.pricePerUnitOf({
                    projectId: revnetId,
                    pricingCurrency: accountingContext.currency,
                    unitCurrency: currency,
                    decimals: decimals
                });

            // Get a reference to the amount of tokens loaned out.
            uint256 tokensLoaned = totalBorrowedFrom[revnetId][source.terminal][source.token];

            borrowedAmount += mulDiv(tokensLoaned, 10 ** decimals, pricePerUnit);
        }
    }

    /// @notice Transfers tokens.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param token The address of the token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    function _transferFor(address from, address payable to, address token, uint256 amount) internal virtual {
        if (from == address(this)) {
            // If the token is native token, assume the `sendValue` standard.
            if (token == JBConstants.NATIVE_TOKEN) return Address.sendValue(to, amount);

            // If the transfer is from this contract, use `safeTransfer`.
            return IERC20(token).safeTransfer(to, amount);
        }

        // If there's sufficient approval, transfer normally.
        if (IERC20(token).allowance(address(from), address(this)) >= amount) {
            return IERC20(token).safeTransferFrom(from, to, amount);
        }

        // Otherwise, attempt to use the `permit2` method.
        PERMIT2.transferFrom(from, to, uint160(amount), token);
    }

    /// @notice Accepts an incoming token.
    /// @param projectId The ID of the project that the transfer is being accepted for.
    /// @param token The token being accepted.
    /// @param amount The number of tokens being accepted.
    /// @param metadata The metadata in which permit2 context is provided.
    /// @return amount The number of tokens which have been accepted.
    function _acceptFundsFor(
        uint256 projectId,
        address token,
        uint256 amount,
        JBSingleAllowance memory allowance
    )
        internal
        returns (uint256)
    {
        // If the token is the native token, override `amount` with `msg.value`.
        if (token == JBConstants.NATIVE_TOKEN) return msg.value;

        // If the token is not native, revert if there is a non-zero `msg.value`.
        if (msg.value != 0) revert NO_MSG_VALUE_ALLOWED();

        // Check if the metadata contains permit data.
        if (allowance.amount != 0) {
            // Make sure the permit allowance is enough for this payment. If not we revert early.
            if (allowance.amount < amount) {
                revert PERMIT_ALLOWANCE_NOT_ENOUGH();
            }

            // Keep a reference to the permit rules.
            IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: token,
                    amount: allowance.amount,
                    expiration: allowance.expiration,
                    nonce: allowance.nonce
                }),
                spender: address(this),
                sigDeadline: allowance.sigDeadline
            });

            // Set the allowance to `spend` tokens for the user.
            try PERMIT2.permit({owner: _msgSender(), permitSingle: permitSingle, signature: allowance.signature}) {}
                catch (bytes memory) {}
        }

        // Get a reference to the balance before receiving tokens.
        uint256 balanceBefore = _balanceOf(token);

        // Transfer tokens to this terminal from the msg sender.
        _transferFrom({from: _msgSender(), to: payable(address(this)), token: token, amount: amount});

        // The amount should reflect the change in balance.
        return _balanceOf(token) - balanceBefore;
    }
}
