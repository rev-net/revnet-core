// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBTokenUriResolver} from "@bananapus/core/src/interfaces/IJBTokenUriResolver.sol";
import {JBCashOuts} from "@bananapus/core/src/libraries/JBCashOuts.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBFees} from "@bananapus/core/src/libraries/JBFees.sol";
import {JBRulesetMetadataResolver} from "@bananapus/core/src/libraries/JBRulesetMetadataResolver.sol";
import {JBSurplus} from "@bananapus/core/src/libraries/JBSurplus.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBRuleset} from "@bananapus/core/src/structs/JBRuleset.sol";
import {JBSingleAllowance} from "@bananapus/core/src/structs/JBSingleAllowance.sol";

import {IREVDeployer} from "./interfaces/IREVDeployer.sol";
import {IREVLoans} from "./interfaces/IREVLoans.sol";
import {REVLoan} from "./structs/REVLoan.sol";
import {REVLoanSource} from "./structs/REVLoanSource.sol";

/// @notice A contract for borrowing from revnets.
/// @dev Tokens used as collateral are burned, and reminted when the loan is paid off. This keeps the revnet's token
/// structure orderly.
/// @dev The borrowable amount is the same as the cash out amount.
/// @dev An upfront fee is taken when a loan is created. 2.5% is charged by the underlying protocol, 2.5% is charged
/// by the
/// revnet issuing the loan, and a variable amount charged by the revnet that receives the fees. This variable amount is
/// chosen by the borrower, the more paid upfront, the longer the prepaid duration. The loan can be repaid anytime
/// within the prepaid duration without additional fees.
/// After the prepaid duration, the loan will increasingly cost more to pay off. After 10 years, the loan collateral
/// cannot be
/// recouped.
/// @dev The loaned amounts include the fees taken, meaning the amount paid back is the amount borrowed plus the fees.
contract REVLoans is ERC721, ERC2771Context, IREVLoans, Ownable {
    // A library that parses the packed ruleset metadata into a friendlier format.
    using JBRulesetMetadataResolver for JBRuleset;

    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error REVLoans_CollateralExceedsLoan(uint256 collateralToReturn, uint256 loanCollateral);
    error REVLoans_CollateralRequired();
    error REVLoans_InvalidPrepaidFeePercent(uint256 prepaidFeePercent, uint256 min, uint256 max);
    error REVLoans_NotEnoughCollateral();
    error REVLoans_OverflowAlert(uint256 value, uint256 limit);
    error REVLoans_OverMaxRepayBorrowAmount(uint256 maxRepayBorrowAmount, uint256 repayBorrowAmount);
    error REVLoans_PermitAllowanceNotEnough(uint256 allowanceAmount, uint256 requiredAmount);
    error REVLoans_NoMsgValueAllowed();
    error REVLoans_LoanExpired(uint256 timeSinceLoanCreated, uint256 loanLiquidationDuration);
    error REVLoans_Unauthorized(address caller, address owner);
    error REVLoans_UnderMinBorrowAmount(uint256 minBorrowAmount, uint256 borrowAmount);

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @dev After the prepaid duration, the loan will cost more to pay off. After 10 years, the loan
    /// collateral cannot be recouped. This means paying 50% of the loan amount upfront will pay for having access to
    /// the remaining 50% for 10 years,
    /// whereas paying 0% of the loan upfront will cost 100% of the loan amount to be paid off after 10 years. After 10
    /// years with repayment, both loans cost 100% and are liquidated.
    uint256 public constant override LOAN_LIQUIDATION_DURATION = 3650 days;

    /// @dev The maximum amount of a loan that can be prepaid at the time of borrowing, in terms of JBConstants.MAX_FEE.
    uint256 public constant override MAX_PREPAID_FEE_PERCENT = 500;

    /// @dev A fee of 0.5% is charged by the $REV revnet.
    uint256 public constant override REV_PREPAID_FEE_PERCENT = 5; // 0.5%

    /// @dev A fee of 2.5% is charged by the loan's source upfront.
    uint256 public constant override SOURCE_MIN_PREPAID_FEE_PERCENT = 25; // 2.5%

    //*********************************************************************//
    // -------------------- private constant properties ------------------ //
    //*********************************************************************//

    /// @notice Just a kind reminder to our readers.
    /// @dev Used in loan token ID generation.
    uint256 private constant _ONE_TRILLION = 1_000_000_000_000;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The permit2 utility.
    IPermit2 public immutable override PERMIT2;

    /// @notice The controller of revnets that use this loans contract.
    IJBController public immutable override CONTROLLER;

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IREVDeployer public immutable override DEPLOYER;

    /// @notice The directory of terminals and controllers for revnets.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice A contract that stores prices for each revnet.
    IJBPrices public immutable override PRICES;

    /// @notice The ID of the REV revnet that will receive the fees.
    uint256 public immutable override REV_ID;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice An indication if a revnet currently has outstanding loans from the specified terminal in the specified
    /// token.
    /// @custom:param revnetId The ID of the revnet issuing the loan.
    /// @custom:param terminal The terminal that the loan is issued from.
    /// @custom:param token The token being loaned.
    mapping(uint256 revnetId => mapping(IJBPayoutTerminal terminal => mapping(address token => bool))) public override
        isLoanSourceOf;

    /// @notice The amount of loans that have been created.
    /// @custom:param revnetId The ID of the revnet to get the number of loans from.
    mapping(uint256 revnetId => uint256) public override numberOfLoansFor;

    /// @notice The contract resolving each project ID to its ERC721 URI.
    IJBTokenUriResolver public override tokenUriResolver;

    /// @notice The total amount loaned out by a revnet from a specified terminal in a specified token.
    /// @custom:param revnetId The ID of the revnet issuing the loan.
    /// @custom:param terminal The terminal that the loan is issued from.
    /// @custom:param token The token being loaned.
    mapping(uint256 revnetId => mapping(IJBPayoutTerminal terminal => mapping(address token => uint256)))
        public
        override totalBorrowedFrom;

    /// @notice The total amount of collateral supporting a revnet's loans.
    /// @custom:param revnetId The ID of the revnet issuing the loan.
    mapping(uint256 revnetId => uint256) public override totalCollateralOf;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice The sources of each revnet's loan.
    /// @custom:member revnetId The ID of the revnet issuing the loan.
    mapping(uint256 revnetId => REVLoanSource[]) internal _loanSourcesOf;

    /// @notice The loans.
    /// @custom:member The ID of the loan.
    mapping(uint256 loanId => REVLoan) internal _loanOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The amount that can be borrowed from a revnet.
    /// @param revnetId The ID of the revnet to check for borrowable assets from.
    /// @param collateralAmount The amount of collateral used to secure the loan.
    /// @param decimals The decimals the resulting fixed point value will include.
    /// @param currency The currency that the resulting amount should be in terms of.
    /// @return borrowableAmount The amount that can be borrowed from the revnet.
    function borrowableAmountFrom(
        uint256 revnetId,
        uint256 collateralAmount,
        uint256 decimals,
        uint256 currency
    )
        external
        view
        returns (uint256)
    {
        // Keep a reference to the current stage.
        (JBRuleset memory currentStage,) = CONTROLLER.currentRulesetOf(revnetId);

        return _borrowableAmountFrom({
            revnetId: revnetId,
            collateralAmount: collateralAmount,
            pendingAutoIssuanceTokens: DEPLOYER.unrealizedAutoIssuanceAmountOf(revnetId),
            decimals: decimals,
            currency: currency,
            currentStage: currentStage,
            terminals: DIRECTORY.terminalsOf(revnetId)
        });
    }

    /// @notice Get a loan.
    /// @custom:member The ID of the loan.
    function loanOf(uint256 loanId) external view override returns (REVLoan memory) {
        return _loanOf[loanId];
    }

    /// @notice The sources of each revnet's loan.
    /// @custom:member revnetId The ID of the revnet issuing the loan.
    function loanSourcesOf(uint256 revnetId) external view override returns (REVLoanSource[] memory) {
        return _loanSourcesOf[revnetId];
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Determines the source fee amount for a loan being paid off a certain amount.
    /// @param loan The loan having its source fee amount determined.
    /// @param amount The amount being paid off.
    /// @return sourceFeeAmount The source fee amount for the loan.
    function determineSourceFeeAmount(REVLoan memory loan, uint256 amount) public view returns (uint256) {
        return _determineSourceFeeAmount(loan, amount);
    }

    /// @notice Returns the URI where the ERC-721 standard JSON of a loan is hosted.
    /// @param loanId The ID of the loan to get a URI of.
    /// @return The token URI to use for the provided `loanId`.
    function tokenURI(uint256 loanId) public view override returns (string memory) {
        // Keep a reference to the resolver.
        IJBTokenUriResolver resolver = tokenUriResolver;

        // If there's no resolver, there's no URI.
        if (resolver == IJBTokenUriResolver(address(0))) return "";

        // Return the resolved URI.
        return resolver.getUri(loanId);
    }

    /// @notice The revnet ID for the loan with the provided loan ID.
    /// @param loanId The loan ID of the loan to get the revent ID of.
    /// @return The ID of the revnet.
    function revnetIdOfLoanWith(uint256 loanId) public pure override returns (uint256) {
        return loanId / _ONE_TRILLION;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice Checks this contract's balance of a specific token.
    /// @param token The address of the token to get this contract's balance of.
    /// @return This contract's balance.
    function _balanceOf(address token) internal view returns (uint256) {
        // If the `token` is native, get the native token balance.
        return token == JBConstants.NATIVE_TOKEN ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /// @dev The amount that can be borrowed from a revnet given a certain amount of collateral.
    /// @param revnetId The ID of the revnet to check for borrowable assets from.
    /// @param collateralAmount The amount of collateral that the loan will be collateralized with.
    /// @param currentStage The current stage of the revnet.
    /// @param pendingAutoIssuanceTokens The amount of tokens pending auto issuance from the revnet.
    /// @param decimals The decimals the resulting fixed point value will include.
    /// @param currency The currency that the resulting amount should be in terms of.
    /// @param terminals The terminals that the funds are being borrowed from.
    /// @return borrowableAmount The amount that can be borrowed from the revnet.
    function _borrowableAmountFrom(
        uint256 revnetId,
        uint256 collateralAmount,
        uint256 pendingAutoIssuanceTokens,
        uint256 decimals,
        uint256 currency,
        JBRuleset memory currentStage,
        IJBTerminal[] memory terminals
    )
        internal
        view
        returns (uint256)
    {
        // Get the surplus of all the revnet's terminals in terms of the native currency.
        uint256 totalSurplus = JBSurplus.currentSurplusOf({
            projectId: revnetId,
            terminals: terminals,
            accountingContexts: new JBAccountingContext[](0),
            decimals: decimals,
            currency: currency
        });

        // Get the total amount the revnet currently has loaned out, in terms of the native currency with 18
        // decimals.
        uint256 totalBorrowed = _totalBorrowedFrom({revnetId: revnetId, decimals: decimals, currency: currency});

        // Get the total amount of tokens in circulation.
        uint256 totalSupply = CONTROLLER.totalTokenSupplyWithReservedTokensOf(revnetId);

        // Get a refeerence to the collateral being used to secure loans.
        uint256 totalCollateral = totalCollateralOf[revnetId];

        // Proportional.
        return JBCashOuts.cashOutFrom({
            surplus: totalSurplus + totalBorrowed,
            cashOutCount: collateralAmount,
            totalSupply: totalSupply + totalCollateral + pendingAutoIssuanceTokens,
            cashOutTaxRate: currentStage.cashOutTaxRate()
        });
    }

    /// @notice The amount of the loan that should be borrowed for the given collateral amount.
    /// @param loan The loan having its borrow amount determined.
    /// @param revnetId The ID of the revnet to check for borrowable assets from.
    /// @param collateralAmount The amount of collateral that the loan will be collateralized with.
    /// @return borrowAmount The amount of the loan that should be borrowed.
    function _borrowAmountFrom(
        REVLoan storage loan,
        uint256 revnetId,
        uint256 collateralAmount
    )
        internal
        view
        returns (uint256)
    {
        // Get a reference to the accounting context for the source.
        JBAccountingContext memory accountingContext =
            loan.source.terminal.accountingContextForTokenOf({projectId: revnetId, token: loan.source.token});

        // Keep a reference to the pending auto issuance tokens.
        uint256 pendingAutoIssuanceTokens = DEPLOYER.unrealizedAutoIssuanceAmountOf(revnetId);

        // Keep a reference to the current stage.
        (JBRuleset memory currentStage,) = CONTROLLER.currentRulesetOf(revnetId);

        // Keep a reference to the revnet's terminals.
        IJBTerminal[] memory terminals = DIRECTORY.terminalsOf(revnetId);

        return _borrowableAmountFrom({
            revnetId: revnetId,
            collateralAmount: collateralAmount,
            pendingAutoIssuanceTokens: pendingAutoIssuanceTokens,
            decimals: accountingContext.decimals,
            currency: accountingContext.currency,
            currentStage: currentStage,
            terminals: terminals
        });
    }

    /// @dev `ERC-2771` specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }

    /// @notice Determines the source fee amount for a loan being paid off a certain amount.
    /// @param loan The loan having its source fee amount determined.
    /// @param amount The amount being paid off.
    /// @return sourceFeeAmount The source fee amount for the loan.
    function _determineSourceFeeAmount(
        REVLoan memory loan,
        uint256 amount
    )
        internal
        view
        returns (uint256 sourceFeeAmount)
    {
        // Keep a reference to the time since the loan was created.
        uint256 timeSinceLoanCreated = block.timestamp - loan.createdAt;

        // If the loan period has passed the prepaid time frame, take a fee.
        if (timeSinceLoanCreated > loan.prepaidDuration) {
            // If the loan period has passed the liqidation time frame, do not allow loan management.
            if (timeSinceLoanCreated > LOAN_LIQUIDATION_DURATION) {
                revert REVLoans_LoanExpired(timeSinceLoanCreated, LOAN_LIQUIDATION_DURATION);
            }

            // Get a reference to the amount prepaid for the full loan.
            uint256 prepaid = JBFees.feeAmountFrom({amount: loan.amount, feePercent: loan.prepaidFeePercent});

            uint256 fullSourceFeeAmount = JBFees.feeAmountFrom({
                amount: loan.amount - prepaid,
                feePercent: mulDiv(timeSinceLoanCreated, JBConstants.MAX_FEE, LOAN_LIQUIDATION_DURATION)
            });

            // Get a reference to the amount that would have to be paid down to make the loan fully paid.
            uint256 amountInFull = loan.amount + fullSourceFeeAmount;

            // Calculate the source fee amount for the amount being paid off.
            sourceFeeAmount = mulDiv(fullSourceFeeAmount, amount, amountInFull);
        }
    }

    /// @notice Generate a ID for a loan given a revnet ID and a loan number within that revnet.
    /// @param revnetId The ID of the revnet to generate a loan ID for.
    /// @param loanNumber The loan number of the loan within the revnet.
    /// @return The token ID of the 721.
    function _generateLoanId(uint256 revnetId, uint256 loanNumber) internal pure returns (uint256) {
        return (revnetId * _ONE_TRILLION) + loanNumber;
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
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
        REVLoanSource[] memory sources = _loanSourcesOf[revnetId];

        // Iterate over all sources being used to loaned out.
        for (uint256 i; i < sources.length; i++) {
            // Get a reference to the token being iterated on.
            REVLoanSource memory source = sources[i];

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

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//
    
    /// @param deployer A contract from which revnets using this loans contract are deployed.
    /// @param revId The ID of the REV revnet that will receive the fees.
    /// @param owner The owner of the contract that can set the URI resolver.
    /// @param permit2 A permit2 utility.
    /// @param trustedForwarder A trusted forwarder of transactions to this contract.
    constructor(
        IREVDeployer deployer,
        uint256 revId,
        address owner,
        IPermit2 permit2,
        address trustedForwarder
    )
        ERC721("REV Loans", "$REVLOAN")
        ERC2771Context(trustedForwarder)
        Ownable(owner)
    {
        DEPLOYER = deployer;
        CONTROLLER = deployer.CONTROLLER();
        DIRECTORY = deployer.DIRECTORY();
        PRICES = deployer.CONTROLLER().PRICES();
        REV_ID = revId;
        PERMIT2 = permit2;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Open a loan by borrowing from a revnet.
    /// @param revnetId The ID of the revnet being borrowed from.
    /// @param source The source of the loan being borrowed.
    /// @param minBorrowAmount The minimum amount being borrowed, denominated in the currency of the source's accounting
    /// context.
    /// @param collateralAmount The amount of tokens to use as collateral for the loan.
    /// @param beneficiary The address that'll receive the borrowed funds and the tokens resulting from fee payments.
    /// @param prepaidFeePercent The fee percent that will be charged upfront from the revnet being borrowed from.
    /// Prepaying a fee is cheaper than paying later.
    /// @return loanId The ID of the loan created from borrowing.
    /// @return loan The loan created from borrowing.
    function borrowFrom(
        uint256 revnetId,
        REVLoanSource calldata source,
        uint256 minBorrowAmount,
        uint256 collateralAmount,
        address payable beneficiary,
        uint256 prepaidFeePercent
    )
        public
        override
        returns (uint256 loanId, REVLoan memory)
    {
        // Make sure the prepaid fee percent is between 0 and 20%. Meaning an 16 year loan can be paid upfront with a
        // payment of 50% of the borrowed assets, the cheapest possible rate.
        if (prepaidFeePercent < SOURCE_MIN_PREPAID_FEE_PERCENT || prepaidFeePercent > MAX_PREPAID_FEE_PERCENT) {
            revert REVLoans_InvalidPrepaidFeePercent(
                prepaidFeePercent, SOURCE_MIN_PREPAID_FEE_PERCENT, MAX_PREPAID_FEE_PERCENT
            );
        }

        // Get a reference to the loan ID.
        loanId = _generateLoanId({revnetId: revnetId, loanNumber: ++numberOfLoansFor[revnetId]});

        // Mint the loan.
        _mint({to: _msgSender(), tokenId: loanId});

        // Get a reference to the loan being created.
        REVLoan storage loan = _loanOf[loanId];

        // Set the loan's values.
        loan.source = source;
        loan.createdAt = uint40(block.timestamp);
        loan.prepaidFeePercent = uint16(prepaidFeePercent);
        loan.prepaidDuration = uint32(mulDiv(prepaidFeePercent, LOAN_LIQUIDATION_DURATION, MAX_PREPAID_FEE_PERCENT));

        // Get the amount of the loan.
        uint256 borrowAmount = _borrowAmountFrom({loan: loan, revnetId: revnetId, collateralAmount: collateralAmount});

        // Make sure the minimum borrow amount is met.
        if (borrowAmount < minBorrowAmount) revert REVLoans_UnderMinBorrowAmount(minBorrowAmount, borrowAmount);

        // Get the amount of additional fee to take for the revnet issuing the loan.
        uint256 sourceFeeAmount = JBFees.feeAmountFrom({amount: borrowAmount, feePercent: prepaidFeePercent});

        // Borrow the amount.
        _adjust({
            loan: loan,
            revnetId: revnetId,
            newBorrowAmount: borrowAmount,
            newCollateralAmount: collateralAmount,
            sourceFeeAmount: sourceFeeAmount,
            beneficiary: beneficiary
        });

        emit Borrow({
            loanId: loanId,
            revnetId: revnetId,
            loan: loan,
            source: source,
            borrowAmount: borrowAmount,
            collateralAmount: collateralAmount,
            sourceFeeAmount: sourceFeeAmount,
            beneficiary: beneficiary,
            caller: _msgSender()
        });

        return (loanId, loan);
    }

    /// @notice Cleans up any liquiditated loans.
    /// @dev Since some loans may be reallocated or paid off, loans within startingLoanId and startingLoanId + count may
    /// be skipped, so choose these parameters carefully to avoid extra gas usage.
    /// @param revnetId The ID of the revnet to liquidate loans from.
    /// @param startingLoanId The ID of the loan to start iterating from.
    /// @param count The amount of loans iterate over since the last liquidated loan.
    function liquidateExpiredLoansFrom(uint256 revnetId, uint256 startingLoanId, uint256 count) external override {
        // Iterate over the desired number of loans to check for liquidation.
        for (uint256 i; i < count; i++) {
            // Get a reference to the next loan ID.
            uint256 loanId = _generateLoanId({revnetId: revnetId, loanNumber: startingLoanId + i});

            // Get a reference to the loan being iterated on.
            REVLoan memory loan = _loanOf[loanId];

            // If the loan doesn't exist, there's nothing left to liquidate.
            // slither-disable-next-line incorrect-equality
            if (loan.createdAt == 0) break;

            // Keep a reference to the loan's owner.
            address owner = _ownerOf(loanId);

            // If the loan is already burned, or if it hasn't passed its liquidation duration, continue.
            if (owner == address(0) || (block.timestamp <= loan.createdAt + LOAN_LIQUIDATION_DURATION)) continue;

            // Burn the loan.
            _burn(loanId);

            // If the loan has been paid back and there is still leftover collateral, return it to the owner.
            // slither-disable-next-line incorrect-equality
            if (loan.collateral > 0) {
                // slither-disable-next-line incorrect-equality
                if (loan.amount == 0) {
                    // Return the collateral to the owner.
                    _returnCollateralFrom({
                        revnetId: revnetId,
                        collateralAmount: loan.collateral,
                        beneficiary: payable(owner)
                    });
                } else {
                    // Decrement the total amount of collateral tokens supporting loans from this revnet.
                    totalCollateralOf[revnetId] -= loan.collateral;
                }
            }

            if (loan.amount > 0) {
                // Decrement the amount loaned.
                totalBorrowedFrom[revnetId][loan.source.terminal][loan.source.token] -= loan.amount;
            }

            emit Liquidate({loanId: loanId, revnetId: revnetId, loan: loan, caller: _msgSender()});
        }
    }

    /// @notice Refinances a loan by transferring extra collateral from an existing loan to a new loan.
    /// @dev Useful if a loan's collateral has gone up in value since the loan was created.
    /// @dev Refinancing a loan will burn the original and create two new loans.
    /// @param loanId The ID of the loan to reallocate collateral from.
    /// @param collateralAmountToTransfer The amount of collateral to transfer from the original loan.
    /// @param source The source of the loan to create.
    /// @param minBorrowAmount The minimum amount being borrowed, denominated in the currency of the source's accounting
    /// context.
    /// @param collateralAmountToAdd The amount of collateral to add to the loan.
    /// @param beneficiary The address that'll receive the borrowed funds and the tokens resulting from fee payments.
    /// @param prepaidFeePercent The fee percent that will be charged upfront from the revnet being borrowed from.
    /// @return reallocatedLoanId The ID of the loan being reallocated.
    /// @return newLoanId The ID of the new loan.
    /// @return reallocatedLoan The loan being reallocated.
    /// @return newLoan The new loan created from reallocating collateral.
    function reallocateCollateralFromLoan(
        uint256 loanId,
        uint256 collateralAmountToTransfer,
        REVLoanSource calldata source,
        uint256 minBorrowAmount,
        uint256 collateralAmountToAdd,
        address payable beneficiary,
        uint256 prepaidFeePercent
    )
        external
        payable
        override
        returns (uint256 reallocatedLoanId, uint256 newLoanId, REVLoan memory reallocatedLoan, REVLoan memory newLoan)
    {
        // Make sure only the loan's owner can manage it.
        if (_ownerOf(loanId) != _msgSender()) revert REVLoans_Unauthorized(_msgSender(), _ownerOf(loanId));

        // Keep a reference to the revnet ID of the loan being reallocated.
        uint256 revnetId = revnetIdOfLoanWith(loanId);

        // Refinance the loan.
        (reallocatedLoanId, reallocatedLoan) = _reallocateCollateralFromLoan({
            loanId: loanId,
            revnetId: revnetId,
            collateralAmountToRemove: collateralAmountToTransfer
        });

        // Make a new loan with the leftover collateral from reallocating.
        (newLoanId, newLoan) = borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: minBorrowAmount,
            collateralAmount: collateralAmountToTransfer + collateralAmountToAdd,
            beneficiary: beneficiary,
            prepaidFeePercent: prepaidFeePercent
        });
    }

    /// @notice Allows the owner of a loan to pay it back or receive returned collateral no longer necessary to support
    /// the loan.
    /// @param loanId The ID of the loan being adjusted.
    /// @param maxRepayBorrowAmount The maximum amount being paid off, denominated in the currency of the source's
    /// accounting context.
    /// @param collateralAmountToReturn The amount of collateral to return being returned from the loan.
    /// @param beneficiary The address receiving the returned collateral and any tokens resulting from paying fees.
    /// @param allowance An allowance to faciliate permit2 interactions.
    /// @return paidOffLoanId The ID of the loan after it's been paid off.
    /// @return paidOffloan The loan after it's been paid off.
    function repayLoan(
        uint256 loanId,
        uint256 maxRepayBorrowAmount,
        uint256 collateralAmountToReturn,
        address payable beneficiary,
        JBSingleAllowance calldata allowance
    )
        external
        payable
        override
        returns (uint256, REVLoan memory)
    {
        // Make sure only the loan's owner can manage it.
        if (_ownerOf(loanId) != _msgSender()) revert REVLoans_Unauthorized(_msgSender(), _ownerOf(loanId));

        // Keep a reference to the fee being iterated on.
        REVLoan storage loan = _loanOf[loanId];

        if (collateralAmountToReturn > loan.collateral) {
            revert REVLoans_CollateralExceedsLoan(collateralAmountToReturn, loan.collateral);
        }

        // Accept the funds that'll be used to pay off loans.
        maxRepayBorrowAmount =
            _acceptFundsFor({token: loan.source.token, amount: maxRepayBorrowAmount, allowance: allowance});

        // Get the new borrow amount.
        uint256 newBorrowAmount = _borrowAmountFrom({
            loan: loan,
            revnetId: revnetIdOfLoanWith(loanId),
            collateralAmount: loan.collateral - collateralAmountToReturn
        });

        // Get the amount of the loan being repaid.
        uint256 repayBorrowAmount = loan.amount - newBorrowAmount;

        // Make sure the minimum borrow amount is met.
        if (repayBorrowAmount > maxRepayBorrowAmount) {
            revert REVLoans_OverMaxRepayBorrowAmount(maxRepayBorrowAmount, repayBorrowAmount);
        }

        _repayLoan({
            loanId: loanId,
            loan: loan,
            repayBorrowAmount: repayBorrowAmount,
            collateralAmountToReturn: collateralAmountToReturn,
            beneficiary: beneficiary
        });

        if (maxRepayBorrowAmount > repayBorrowAmount) {
            _transferFrom({
                from: address(this),
                to: payable(_msgSender()),
                token: loan.source.token,
                amount: maxRepayBorrowAmount - repayBorrowAmount
            });
        }
    }

    /// @notice Sets the address of the resolver used to retrieve the tokenURI of loans.
    /// @param resolver The address of the new resolver.
    function setTokenUriResolver(IJBTokenUriResolver resolver) external override onlyOwner {
        // Store the new resolver.
        tokenUriResolver = resolver;

        emit SetTokenUriResolver({resolver: resolver, caller: _msgSender()});
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Adds collateral to a loan.
    /// @param revnetId The ID of the revnet the loan is being added in.
    /// @param amount The new amount of collateral being added to the loan.
    function _addCollateralTo(uint256 revnetId, uint256 amount) internal {
        // Increment the total amount of collateral tokens.
        totalCollateralOf[revnetId] += amount;

        // Burn the tokens that are tracked as collateral.
        CONTROLLER.burnTokensOf({
            holder: _msgSender(),
            projectId: revnetId,
            tokenCount: amount,
            memo: "Adding collateral to loan"
        });
    }

    /// @notice Add a new amount to the loan that is greater than the previous amount.
    /// @param loan The loan being added to.
    /// @param revnetId The ID of the revnet the loan is being added in.
    /// @param addedBorrowAmount The amount being added to the loan, denominated in the currency of the source's
    /// accounting
    /// context.
    /// @param sourceFeeAmount The amount of the fee being taken from the revnet acting as the source of the loan.
    /// @param feeTerminal The terminal that the fee will be paid to.
    /// @param beneficiary The address receiving the returned collateral and any tokens resulting from paying fees.
    function _addTo(
        REVLoan memory loan,
        uint256 revnetId,
        uint256 addedBorrowAmount,
        uint256 sourceFeeAmount,
        IJBTerminal feeTerminal,
        address payable beneficiary
    )
        internal
    {
        // Register the source if this is the first time its being used for this revnet.
        if (!isLoanSourceOf[revnetId][loan.source.terminal][loan.source.token]) {
            isLoanSourceOf[revnetId][loan.source.terminal][loan.source.token] = true;
            _loanSourcesOf[revnetId].push(REVLoanSource({token: loan.source.token, terminal: loan.source.terminal}));
        }

        // Increment the amount of the token borrowed from the revnet from the terminal.
        totalBorrowedFrom[revnetId][loan.source.terminal][loan.source.token] += addedBorrowAmount;

        // Get a reference to the accounting context for the source.
        JBAccountingContext memory accountingContext =
            loan.source.terminal.accountingContextForTokenOf({projectId: revnetId, token: loan.source.token});

        // Pull the amount to be loaned out of the revnet. This will incure the protocol fee.
        // slither-disable-next-line unused-return
        loan.source.terminal.useAllowanceOf({
            projectId: revnetId,
            token: loan.source.token,
            amount: addedBorrowAmount,
            currency: accountingContext.currency,
            minTokensPaidOut: 0,
            beneficiary: payable(address(this)),
            feeBeneficiary: beneficiary,
            memo: "Lending out to a borrower"
        });

        // Get the amount of additional fee to take for REV.
        uint256 revFeeAmount = JBFees.feeAmountFrom({amount: addedBorrowAmount, feePercent: REV_PREPAID_FEE_PERCENT});

        // Increase the allowance for the beneficiary.
        uint256 payValue = _beforeTransferTo({to: address(feeTerminal), token: loan.source.token, amount: revFeeAmount});

        // Pay the fee. Send the REV to the msg.sender.
        // slither-disable-next-line arbitrary-send-eth,unused-return
        try feeTerminal.pay{value: payValue}({
            projectId: REV_ID,
            token: loan.source.token,
            amount: revFeeAmount,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Fee from loan",
            metadata: bytes(abi.encodePacked(revnetId))
        }) {} catch (bytes memory) {}

        // Transfer the remaining balance to the borrower.
        _transferFrom({
            from: address(this),
            to: beneficiary,
            token: loan.source.token,
            amount: _balanceOf(loan.source.token) - sourceFeeAmount
        });
    }

    /// @notice Allows the owner of a loan to pay it back, add more, or receive returned collateral no longer necessary
    /// to support the loan.
    /// @param loan The loan being adjusted.
    /// @param revnetId The ID of the revnet the loan is being adjusted in.
    /// @param newBorrowAmount The new amount of the loan, denominated in the currency of the source's accounting
    /// context.
    /// @param newCollateralAmount The new amount of collateral backing the loan.
    /// @param sourceFeeAmount The amount of the fee being taken from the revnet acting as the source of the loan.
    /// @param beneficiary The address receiving the returned collateral and any tokens resulting from paying fees.
    function _adjust(
        REVLoan storage loan,
        uint256 revnetId,
        uint256 newBorrowAmount,
        uint256 newCollateralAmount,
        uint256 sourceFeeAmount,
        address payable beneficiary
    )
        internal
    {
        // Add to the loan if needed...
        if (newBorrowAmount > loan.amount) {
            // Keep a reference to the fee terminal.
            IJBTerminal feeTerminal = DIRECTORY.primaryTerminalOf(REV_ID, loan.source.token);

            // Add the new amount to the loan.
            _addTo({
                loan: loan,
                revnetId: revnetId,
                addedBorrowAmount: newBorrowAmount - loan.amount,
                sourceFeeAmount: sourceFeeAmount,
                feeTerminal: feeTerminal,
                beneficiary: beneficiary
            });
            // ... or pay off the loan if needed.
        } else if (loan.amount > newBorrowAmount) {
            _removeFrom({loan: loan, revnetId: revnetId, repaidBorrowAmount: loan.amount - newBorrowAmount});
        }

        // Add collateral if needed...
        if (newCollateralAmount > loan.collateral) {
            _addCollateralTo({revnetId: revnetId, amount: newCollateralAmount - loan.collateral});
            // ... or return collateral if needed.
        } else if (loan.collateral > newCollateralAmount) {
            _returnCollateralFrom({
                revnetId: revnetId,
                collateralAmount: loan.collateral - newCollateralAmount,
                beneficiary: beneficiary
            });
        }

        // Get a reference to the amount remaining in this contract.
        uint256 balance = _balanceOf(loan.source.token);

        // The amount remaining in the contract should be the source fee.
        if (balance > 0) {
            // Increase the allowance for the beneficiary.
            uint256 payValue =
                _beforeTransferTo({to: address(loan.source.terminal), token: loan.source.token, amount: balance});

            // Pay the fee.
            // slither-disable-next-line unused-return
            try loan.source.terminal.pay{value: payValue}({
                projectId: revnetId,
                token: loan.source.token,
                amount: balance,
                beneficiary: beneficiary,
                minReturnedTokens: 0,
                memo: "Fee from loan",
                metadata: bytes(abi.encodePacked(REV_ID))
            }) {} catch (bytes memory) {}
        }

        // Store the loans updated values.
        loan.amount = uint112(newBorrowAmount);
        loan.collateral = uint112(newCollateralAmount);
    }

    /// @notice Accepts an incoming token.
    /// @param token The token being accepted.
    /// @param amount The number of tokens being accepted.
    /// @param allowance The permit2 context.
    /// @return amount The number of tokens which have been accepted.
    function _acceptFundsFor(
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
        if (msg.value != 0) revert REVLoans_NoMsgValueAllowed();

        // Check if the metadata contains permit data.
        if (allowance.amount != 0) {
            // Make sure the permit allowance is enough for this payment. If not we revert early.
            if (allowance.amount < amount) {
                revert REVLoans_PermitAllowanceNotEnough(allowance.amount, amount);
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

    /// @notice Logic to be triggered before transferring tokens from this contract.
    /// @param to The address the transfer is going to.
    /// @param token The token being transferred.
    /// @param amount The number of tokens being transferred, as a fixed point number with the same number of decimals
    /// as the token specifies.
    /// @return payValue The value to attach to the transaction being sent.
    function _beforeTransferTo(address to, address token, uint256 amount) internal returns (uint256) {
        // If the token is the native token, no allowance needed.
        if (token == JBConstants.NATIVE_TOKEN) return amount;
        IERC20(token).safeIncreaseAllowance(to, amount);
        return 0;
    }

    /// @notice Pays down a loan.
    /// @param loanId The ID of the loan being paid down.
    /// @param loan The loan being paid down.
    /// @param repayBorrowAmount The amount being paid down from the loan, denominated in the currency of the source's
    /// accounting context.
    /// @param collateralAmountToReturn The amount of collateral being returned that the loan no longer requires.
    /// @param beneficiary The address receiving the returned collateral and any tokens resulting from paying fees.
    function _repayLoan(
        uint256 loanId,
        REVLoan storage loan,
        uint256 repayBorrowAmount,
        uint256 collateralAmountToReturn,
        address payable beneficiary
    )
        internal
        returns (uint256, REVLoan memory)
    {
        // Keep a reference to the fee that'll be taken.
        uint256 sourceFeeAmount = _determineSourceFeeAmount(loan, repayBorrowAmount);

        // If the amount being paid is greater than the loan's amount, return extra to the payer.
        // amount is msg.value if token == JBConstants.NATIVE_TOKEN
        if (repayBorrowAmount > loan.amount + sourceFeeAmount) {
            _transferFrom({
                from: address(this),
                to: payable(_msgSender()),
                token: loan.source.token,
                amount: repayBorrowAmount - sourceFeeAmount - loan.amount
            });

            // Set the amount as the amount that can be paid off.
            repayBorrowAmount = sourceFeeAmount + loan.amount;
        }

        // Get a reference to the revnet ID.
        uint256 revnetId = revnetIdOfLoanWith(loanId);

        // Burn the original loan.
        _burn(loanId);

        // If the loan will carry no more amount or collateral, store its changes directly.
        // slither-disable-next-line incorrect-equality
        if (repayBorrowAmount - sourceFeeAmount == loan.amount && collateralAmountToReturn == loan.collateral) {
            // Borrow in.
            _adjust({
                loan: loan,
                revnetId: revnetId,
                newBorrowAmount: 0,
                newCollateralAmount: 0,
                sourceFeeAmount: sourceFeeAmount,
                beneficiary: beneficiary
            });

            emit RepayLoan({
                loanId: loanId,
                revnetId: revnetId,
                paidOffLoanId: loanId,
                loan: loan,
                paidOffLoan: loan,
                repayBorrowAmount: repayBorrowAmount,
                sourceFeeAmount: sourceFeeAmount,
                collateralAmountToReturn: collateralAmountToReturn,
                beneficiary: beneficiary,
                caller: _msgSender()
            });

            return (loanId, loan);
        } else {
            // Make a new loan with the remaining amount and collateral.
            // Get a reference to the replacement loan ID.
            uint256 paidOffLoanId = _generateLoanId({revnetId: revnetId, loanNumber: ++numberOfLoansFor[revnetId]});

            // Mint the replacement loan.
            _mint({to: _msgSender(), tokenId: paidOffLoanId});

            // Get a reference to the loan being paid off.
            REVLoan storage paidOffLoan = _loanOf[paidOffLoanId];

            // Set the paid off loan's values the same as the original loan.
            paidOffLoan.amount = loan.amount;
            paidOffLoan.collateral = loan.collateral;
            paidOffLoan.createdAt = loan.createdAt;
            paidOffLoan.prepaidFeePercent = loan.prepaidFeePercent;
            paidOffLoan.prepaidDuration = loan.prepaidDuration;
            paidOffLoan.source = loan.source;

            // Borrow in.
            _adjust({
                loan: paidOffLoan,
                revnetId: revnetId,
                newBorrowAmount: paidOffLoan.amount - (repayBorrowAmount - sourceFeeAmount),
                newCollateralAmount: paidOffLoan.collateral - collateralAmountToReturn,
                sourceFeeAmount: sourceFeeAmount,
                beneficiary: beneficiary
            });

            emit RepayLoan({
                loanId: loanId,
                revnetId: revnetId,
                paidOffLoanId: paidOffLoanId,
                loan: loan,
                paidOffLoan: paidOffLoan,
                repayBorrowAmount: repayBorrowAmount,
                sourceFeeAmount: sourceFeeAmount,
                collateralAmountToReturn: collateralAmountToReturn,
                beneficiary: beneficiary,
                caller: _msgSender()
            });

            return (paidOffLoanId, paidOffLoan);
        }
    }

    /// @notice Reallocates collateral from a loan by making a new loan based on the original, with reduced collateral.
    /// @param loanId The ID of the loan to reallocate collateral from.
    /// @param revnetId The ID of the revnet the loan is from.
    /// @param collateralAmountToRemove The amount of collateral to remove from the loan.
    /// @return reallocatedLoanId The ID of the loan.
    /// @return reallocatedLoan The reallocated loan.
    function _reallocateCollateralFromLoan(
        uint256 loanId,
        uint256 revnetId,
        uint256 collateralAmountToRemove
    )
        internal
        returns (uint256 reallocatedLoanId, REVLoan storage reallocatedLoan)
    {
        // Burn the original loan.
        _burn(loanId);

        // Keep a reference to loan having its collateral reduced.
        REVLoan storage loan = _loanOf[loanId];

        // Make sure there is enough collateral to transfer.
        if (collateralAmountToRemove > loan.collateral) revert REVLoans_NotEnoughCollateral();

        // Make sure there is collateral if the loan has debt.
        if (collateralAmountToRemove == loan.collateral && loan.amount != 0) revert REVLoans_CollateralRequired();

        // Get a reference to the replacement loan ID.
        reallocatedLoanId = _generateLoanId(revnetId, ++numberOfLoansFor[revnetId]);

        // Mint the replacement loan.
        _mint({to: _msgSender(), tokenId: reallocatedLoanId});

        // Get a reference to the loan being created.
        reallocatedLoan = _loanOf[reallocatedLoanId];

        // Set the reallocated loan's values the same as the original loan.
        reallocatedLoan.amount = loan.amount;
        reallocatedLoan.collateral = loan.collateral;
        reallocatedLoan.createdAt = loan.createdAt;
        reallocatedLoan.prepaidFeePercent = loan.prepaidFeePercent;
        reallocatedLoan.prepaidDuration = loan.prepaidDuration;
        reallocatedLoan.source = loan.source;

        uint256 borrowAmount = _borrowAmountFrom({
            loan: reallocatedLoan,
            revnetId: revnetId,
            collateralAmount: reallocatedLoan.collateral - collateralAmountToRemove
        });

        // Reduce the collateral of the replacement loan.
        _adjust({
            loan: reallocatedLoan,
            revnetId: revnetId,
            newBorrowAmount: borrowAmount,
            newCollateralAmount: reallocatedLoan.collateral - collateralAmountToRemove,
            sourceFeeAmount: 0,
            beneficiary: payable(_msgSender()) // use the msgSender as the beneficiary, who will have the returned
                // collateral tokens debited from their balance for the new loan.
        });

        // If the borrow amount is less than the original loan's amount, transfer the difference back to the msg sender.
        if (borrowAmount < reallocatedLoan.amount) {
            _transferFrom({
                from: address(this),
                to: payable(_msgSender()),
                token: loan.source.token,
                amount: reallocatedLoan.amount - borrowAmount
            });

            reallocatedLoan.amount = uint112(borrowAmount);
        }

        emit ReallocateCollateral({
            loanId: loanId,
            revnetId: revnetId,
            reallocatedLoanId: reallocatedLoanId,
            reallocatedLoan: reallocatedLoan,
            removedCollateralAmount: collateralAmountToRemove,
            caller: _msgSender()
        });
    }

    /// @notice Pays off a loan.
    /// @param loan The loan being paid off.
    /// @param revnetId The ID of the revnet the loan is being paid off in.
    /// @param repaidBorrowAmount The amount being paid off, denominated in the currency of the source's accounting
    /// context.
    function _removeFrom(REVLoan memory loan, uint256 revnetId, uint256 repaidBorrowAmount) internal {
        // Decrement the total amount of a token being loaned out by the revnet from its terminal.
        totalBorrowedFrom[revnetId][loan.source.terminal][loan.source.token] -= repaidBorrowAmount;

        // Increase the allowance for the beneficiary.
        uint256 payValue =
            _beforeTransferTo({to: address(loan.source.terminal), token: loan.source.token, amount: repaidBorrowAmount});

        // Add the loaned amount back to the revnet.
        try loan.source.terminal.addToBalanceOf{value: payValue}({
            projectId: revnetId,
            token: loan.source.token,
            amount: repaidBorrowAmount,
            shouldReturnHeldFees: false,
            memo: "Paying off loan",
            metadata: bytes(abi.encodePacked(REV_ID))
        }) {} catch (bytes memory) {}
    }

    /// @notice Returns collateral from a loan.
    /// @param revnetId The ID of the revnet the loan is being returned in.
    /// @param collateralAmount The amount of collateral being returned from the loan.
    /// @param beneficiary The address receiving the returned collateral.
    function _returnCollateralFrom(uint256 revnetId, uint256 collateralAmount, address payable beneficiary) internal {
        // Decrement the total amount of collateral tokens.
        totalCollateralOf[revnetId] -= collateralAmount;

        // Mint the collateral tokens back to the loan payer.
        // slither-disable-next-line unused-return,calls-loop
        CONTROLLER.mintTokensOf({
            projectId: revnetId,
            tokenCount: collateralAmount,
            beneficiary: beneficiary,
            memo: "Removing collateral from loan",
            useReservedPercent: false
        });
    }

    /// @notice Transfers tokens.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param token The address of the token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    function _transferFrom(address from, address payable to, address token, uint256 amount) internal virtual {
        if (from == address(this)) {
            // If the token is native token, assume the `sendValue` standard.
            if (token == JBConstants.NATIVE_TOKEN) return Address.sendValue({recipient: to, amount: amount});

            // If the transfer is from this contract, use `safeTransfer`.
            return IERC20(token).safeTransfer({to: to, value: amount});
        }

        // If there's sufficient approval, transfer normally.
        if (IERC20(token).allowance(address(from), address(this)) >= amount) {
            return IERC20(token).safeTransferFrom({from: from, to: to, value: amount});
        }

        // Make sure the amount being paid is less than the maximum permit2 allowance.
        if (amount > type(uint160).max) revert REVLoans_OverflowAlert(amount, type(uint160).max);

        // Otherwise, attempt to use the `permit2` method.
        PERMIT2.transferFrom({from: from, to: to, amount: uint160(amount), token: token});
    }

    fallback() external payable {}
    receive() external payable {}
}
