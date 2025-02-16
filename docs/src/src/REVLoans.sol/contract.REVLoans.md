# REVLoans
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/REVLoans.sol)

**Inherits:**
ERC721, ERC2771Context, Ownable, [IREVLoans](/src/interfaces/IREVLoans.sol/interface.IREVLoans.md)

A contract for borrowing from revnets.

*Tokens used as collateral are burned, and reminted when the loan is paid off. This keeps the revnet's token
structure orderly.*

*The borrowable amount is the same as the cash out amount.*

*An upfront fee is taken when a loan is created. 2.5% is charged by the underlying protocol, 2.5% is charged
by the
revnet issuing the loan, and a variable amount charged by the revnet that receives the fees. This variable amount is
chosen by the borrower, the more paid upfront, the longer the prepaid duration. The loan can be repaid anytime
within the prepaid duration without additional fees.
After the prepaid duration, the loan will increasingly cost more to pay off. After 10 years, the loan collateral
cannot be
recouped.*

*The loaned amounts include the fees taken, meaning the amount paid back is the amount borrowed plus the fees.*


## State Variables
### LOAN_LIQUIDATION_DURATION
*After the prepaid duration, the loan will cost more to pay off. After 10 years, the loan
collateral cannot be recouped. This means paying 50% of the loan amount upfront will pay for having access to
the remaining 50% for 10 years,
whereas paying 0% of the loan upfront will cost 100% of the loan amount to be paid off after 10 years. After 10
years with repayment, both loans cost 100% and are liquidated.*


```solidity
uint256 public constant override LOAN_LIQUIDATION_DURATION = 3650 days;
```


### MAX_PREPAID_FEE_PERCENT
*The maximum amount of a loan that can be prepaid at the time of borrowing, in terms of JBConstants.MAX_FEE.*


```solidity
uint256 public constant override MAX_PREPAID_FEE_PERCENT = 500;
```


### REV_PREPAID_FEE_PERCENT
*A fee of 0.5% is charged by the $REV revnet.*


```solidity
uint256 public constant override REV_PREPAID_FEE_PERCENT = 5;
```


### MIN_PREPAID_FEE_PERCENT
*A fee of 2.5% is charged by the loan's source upfront.*


```solidity
uint256 public constant override MIN_PREPAID_FEE_PERCENT = 25;
```


### _ONE_TRILLION
Just a kind reminder to our readers.

*Used in loan token ID generation.*


```solidity
uint256 private constant _ONE_TRILLION = 1_000_000_000_000;
```


### PERMIT2
The permit2 utility.


```solidity
IPermit2 public immutable override PERMIT2;
```


### CONTROLLER
The controller of revnets that use this loans contract.


```solidity
IJBController public immutable override CONTROLLER;
```


### REVNETS
Mints ERC-721s that represent project ownership and transfers.


```solidity
IREVDeployer public immutable override REVNETS;
```


### DIRECTORY
The directory of terminals and controllers for revnets.


```solidity
IJBDirectory public immutable override DIRECTORY;
```


### PRICES
A contract that stores prices for each revnet.


```solidity
IJBPrices public immutable override PRICES;
```


### PROJECTS
Mints ERC-721s that represent revnet ownership and transfers.


```solidity
IJBProjects public immutable override PROJECTS;
```


### REV_ID
The ID of the REV revnet that will receive the fees.


```solidity
uint256 public immutable override REV_ID;
```


### isLoanSourceOf
An indication if a revnet currently has outstanding loans from the specified terminal in the specified
token.


```solidity
mapping(uint256 revnetId => mapping(IJBPayoutTerminal terminal => mapping(address token => bool))) public override
    isLoanSourceOf;
```


### numberOfLoansFor
The amount of loans that have been created.


```solidity
mapping(uint256 revnetId => uint256) public override numberOfLoansFor;
```


### tokenUriResolver
The contract resolving each project ID to its ERC721 URI.


```solidity
IJBTokenUriResolver public override tokenUriResolver;
```


### totalBorrowedFrom
The total amount loaned out by a revnet from a specified terminal in a specified token.


```solidity
mapping(uint256 revnetId => mapping(IJBPayoutTerminal terminal => mapping(address token => uint256))) public override
    totalBorrowedFrom;
```


### totalCollateralOf
The total amount of collateral supporting a revnet's loans.


```solidity
mapping(uint256 revnetId => uint256) public override totalCollateralOf;
```


### _loanSourcesOf
The sources of each revnet's loan.

**Note:**
member: revnetId The ID of the revnet issuing the loan.


```solidity
mapping(uint256 revnetId => REVLoanSource[]) internal _loanSourcesOf;
```


### _loanOf
The loans.

**Note:**
member: The ID of the loan.


```solidity
mapping(uint256 loanId => REVLoan) internal _loanOf;
```


## Functions
### constructor


```solidity
constructor(
    IREVDeployer revnets,
    uint256 revId,
    address owner,
    IPermit2 permit2,
    address trustedForwarder
)
    ERC721("REV Loans", "$REVLOAN")
    ERC2771Context(trustedForwarder)
    Ownable(owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnets`|`IREVDeployer`|A contract from which revnets using this loans contract are deployed.|
|`revId`|`uint256`|The ID of the REV revnet that will receive the fees.|
|`owner`|`address`|The owner of the contract that can set the URI resolver.|
|`permit2`|`IPermit2`|A permit2 utility.|
|`trustedForwarder`|`address`|A trusted forwarder of transactions to this contract.|


### borrowableAmountFrom

The amount that can be borrowed from a revnet.


```solidity
function borrowableAmountFrom(
    uint256 revnetId,
    uint256 collateralCount,
    uint256 decimals,
    uint256 currency
)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to check for borrowable assets from.|
|`collateralCount`|`uint256`|The amount of collateral used to secure the loan.|
|`decimals`|`uint256`|The decimals the resulting fixed point value will include.|
|`currency`|`uint256`|The currency that the resulting amount should be in terms of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|borrowableAmount The amount that can be borrowed from the revnet.|


### loanOf

Get a loan.

**Note:**
member: The ID of the loan.


```solidity
function loanOf(uint256 loanId) external view override returns (REVLoan memory);
```

### loanSourcesOf

The sources of each revnet's loan.

**Note:**
member: revnetId The ID of the revnet issuing the loan.


```solidity
function loanSourcesOf(uint256 revnetId) external view override returns (REVLoanSource[] memory);
```

### determineSourceFeeAmount

Determines the source fee amount for a loan being paid off a certain amount.


```solidity
function determineSourceFeeAmount(REVLoan memory loan, uint256 amount) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loan`|`REVLoan`|The loan having its source fee amount determined.|
|`amount`|`uint256`|The amount being paid off.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|sourceFeeAmount The source fee amount for the loan.|


### tokenURI

Returns the URI where the ERC-721 standard JSON of a loan is hosted.


```solidity
function tokenURI(uint256 loanId) public view override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The ID of the loan to get a URI of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token URI to use for the provided `loanId`.|


### revnetIdOfLoanWith

The revnet ID for the loan with the provided loan ID.


```solidity
function revnetIdOfLoanWith(uint256 loanId) public pure override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The loan ID of the loan to get the revent ID of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The ID of the revnet.|


### _balanceOf

Checks this contract's balance of a specific token.


```solidity
function _balanceOf(address token) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to get this contract's balance of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This contract's balance.|


### _borrowableAmountFrom

*The amount that can be borrowed from a revnet given a certain amount of collateral.*


```solidity
function _borrowableAmountFrom(
    uint256 revnetId,
    uint256 collateralCount,
    uint256 decimals,
    uint256 currency,
    IJBTerminal[] memory terminals
)
    internal
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to check for borrowable assets from.|
|`collateralCount`|`uint256`|The amount of collateral that the loan will be collateralized with.|
|`decimals`|`uint256`|The decimals the resulting fixed point value will include.|
|`currency`|`uint256`|The currency that the resulting amount should be in terms of.|
|`terminals`|`IJBTerminal[]`|The terminals that the funds are being borrowed from.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|borrowableAmount The amount that can be borrowed from the revnet.|


### _borrowAmountFrom

The amount of the loan that should be borrowed for the given collateral amount.


```solidity
function _borrowAmountFrom(
    REVLoan storage loan,
    uint256 revnetId,
    uint256 collateralCount
)
    internal
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loan`|`REVLoan`|The loan having its borrow amount determined.|
|`revnetId`|`uint256`|The ID of the revnet to check for borrowable assets from.|
|`collateralCount`|`uint256`|The amount of collateral that the loan will be collateralized with.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|borrowAmount The amount of the loan that should be borrowed.|


### _contextSuffixLength

*`ERC-2771` specifies the context as being a single address (20 bytes).*


```solidity
function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256);
```

### _determineSourceFeeAmount

Determines the source fee amount for a loan being paid off a certain amount.


```solidity
function _determineSourceFeeAmount(
    REVLoan memory loan,
    uint256 amount
)
    internal
    view
    returns (uint256 sourceFeeAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loan`|`REVLoan`|The loan having its source fee amount determined.|
|`amount`|`uint256`|The amount being paid off.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sourceFeeAmount`|`uint256`|The source fee amount for the loan.|


### _generateLoanId

Generate a ID for a loan given a revnet ID and a loan number within that revnet.


```solidity
function _generateLoanId(uint256 revnetId, uint256 loanNumber) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to generate a loan ID for.|
|`loanNumber`|`uint256`|The loan number of the loan within the revnet.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The token ID of the 721.|


### _msgData

The calldata. Preferred to use over `msg.data`.


```solidity
function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|calldata The `msg.data` of this call.|


### _msgSender

The message's sender. Preferred to use over `msg.sender`.


```solidity
function _msgSender() internal view override(ERC2771Context, Context) returns (address sender);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address which sent this call.|


### _totalBorrowedFrom

The total borrowed amount from a revnet.


```solidity
function _totalBorrowedFrom(
    uint256 revnetId,
    uint256 decimals,
    uint256 currency
)
    internal
    view
    returns (uint256 borrowedAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to check for borrowed assets from.|
|`decimals`|`uint256`|The decimals the resulting fixed point value will include.|
|`currency`|`uint256`|The currency the resulting value will be in terms of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`borrowedAmount`|`uint256`|The total amount borrowed.|


### borrowFrom

Open a loan by borrowing from a revnet.


```solidity
function borrowFrom(
    uint256 revnetId,
    REVLoanSource calldata source,
    uint256 minBorrowAmount,
    uint256 collateralCount,
    address payable beneficiary,
    uint256 prepaidFeePercent
)
    public
    override
    returns (uint256 loanId, REVLoan memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet being borrowed from.|
|`source`|`REVLoanSource`|The source of the loan being borrowed.|
|`minBorrowAmount`|`uint256`|The minimum amount being borrowed, denominated in the token of the source's accounting context.|
|`collateralCount`|`uint256`|The amount of tokens to use as collateral for the loan.|
|`beneficiary`|`address payable`|The address that'll receive the borrowed funds and the tokens resulting from fee payments.|
|`prepaidFeePercent`|`uint256`|The fee percent that will be charged upfront from the revnet being borrowed from. Prepaying a fee is cheaper than paying later.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The ID of the loan created from borrowing.|
|`<none>`|`REVLoan`|loan The loan created from borrowing.|


### liquidateExpiredLoansFrom

Cleans up any liquiditated loans.

*Since some loans may be reallocated or paid off, loans within startingLoanId and startingLoanId + count may
be skipped, so choose these parameters carefully to avoid extra gas usage.*


```solidity
function liquidateExpiredLoansFrom(uint256 revnetId, uint256 startingLoanId, uint256 count) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet to liquidate loans from.|
|`startingLoanId`|`uint256`|The ID of the loan to start iterating from.|
|`count`|`uint256`|The amount of loans iterate over since the last liquidated loan.|


### reallocateCollateralFromLoan

Refinances a loan by transferring extra collateral from an existing loan to a new loan.

*Useful if a loan's collateral has gone up in value since the loan was created.*

*Refinancing a loan will burn the original and create two new loans.*


```solidity
function reallocateCollateralFromLoan(
    uint256 loanId,
    uint256 collateralCountToTransfer,
    REVLoanSource calldata source,
    uint256 minBorrowAmount,
    uint256 collateralCountToAdd,
    address payable beneficiary,
    uint256 prepaidFeePercent
)
    external
    payable
    override
    returns (uint256 reallocatedLoanId, uint256 newLoanId, REVLoan memory reallocatedLoan, REVLoan memory newLoan);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The ID of the loan to reallocate collateral from.|
|`collateralCountToTransfer`|`uint256`|The amount of collateral to transfer from the original loan.|
|`source`|`REVLoanSource`|The source of the loan to create.|
|`minBorrowAmount`|`uint256`|The minimum amount being borrowed, denominated in the token of the source's accounting context.|
|`collateralCountToAdd`|`uint256`|The amount of collateral to add to the loan.|
|`beneficiary`|`address payable`|The address that'll receive the borrowed funds and the tokens resulting from fee payments.|
|`prepaidFeePercent`|`uint256`|The fee percent that will be charged upfront from the revnet being borrowed from.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`reallocatedLoanId`|`uint256`|The ID of the loan being reallocated.|
|`newLoanId`|`uint256`|The ID of the new loan.|
|`reallocatedLoan`|`REVLoan`|The loan being reallocated.|
|`newLoan`|`REVLoan`|The new loan created from reallocating collateral.|


### repayLoan

Allows the owner of a loan to pay it back or receive returned collateral no longer necessary to support
the loan.


```solidity
function repayLoan(
    uint256 loanId,
    uint256 maxRepayBorrowAmount,
    uint256 collateralCountToReturn,
    address payable beneficiary,
    JBSingleAllowance calldata allowance
)
    external
    payable
    override
    returns (uint256 paidOffLoanId, REVLoan memory paidOffloan);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The ID of the loan being adjusted.|
|`maxRepayBorrowAmount`|`uint256`|The maximum amount being paid off, denominated in the token of the source's accounting context.|
|`collateralCountToReturn`|`uint256`|The amount of collateral to return being returned from the loan.|
|`beneficiary`|`address payable`|The address receiving the returned collateral and any tokens resulting from paying fees.|
|`allowance`|`JBSingleAllowance`|An allowance to faciliate permit2 interactions.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`paidOffLoanId`|`uint256`|The ID of the loan after it's been paid off.|
|`paidOffloan`|`REVLoan`|The loan after it's been paid off.|


### setTokenUriResolver

Sets the address of the resolver used to retrieve the tokenURI of loans.


```solidity
function setTokenUriResolver(IJBTokenUriResolver resolver) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`resolver`|`IJBTokenUriResolver`|The address of the new resolver.|


### _addCollateralTo

Adds collateral to a loan.


```solidity
function _addCollateralTo(uint256 revnetId, uint256 amount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet the loan is being added in.|
|`amount`|`uint256`|The new amount of collateral being added to the loan.|


### _addTo

Add a new amount to the loan that is greater than the previous amount.


```solidity
function _addTo(
    REVLoan memory loan,
    uint256 revnetId,
    uint256 addedBorrowAmount,
    uint256 sourceFeeAmount,
    IJBTerminal feeTerminal,
    address payable beneficiary
)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loan`|`REVLoan`|The loan being added to.|
|`revnetId`|`uint256`|The ID of the revnet the loan is being added in.|
|`addedBorrowAmount`|`uint256`|The amount being added to the loan, denominated in the token of the source's accounting context.|
|`sourceFeeAmount`|`uint256`|The amount of the fee being taken from the revnet acting as the source of the loan.|
|`feeTerminal`|`IJBTerminal`|The terminal that the fee will be paid to.|
|`beneficiary`|`address payable`|The address receiving the returned collateral and any tokens resulting from paying fees.|


### _adjust

Allows the owner of a loan to pay it back, add more, or receive returned collateral no longer necessary
to support the loan.


```solidity
function _adjust(
    REVLoan storage loan,
    uint256 revnetId,
    uint256 newBorrowAmount,
    uint256 newCollateralCount,
    uint256 sourceFeeAmount,
    address payable beneficiary
)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loan`|`REVLoan`|The loan being adjusted.|
|`revnetId`|`uint256`|The ID of the revnet the loan is being adjusted in.|
|`newBorrowAmount`|`uint256`|The new amount of the loan, denominated in the token of the source's accounting context.|
|`newCollateralCount`|`uint256`|The new amount of collateral backing the loan.|
|`sourceFeeAmount`|`uint256`|The amount of the fee being taken from the revnet acting as the source of the loan.|
|`beneficiary`|`address payable`|The address receiving the returned collateral and any tokens resulting from paying fees.|


### _acceptFundsFor

Accepts an incoming token.


```solidity
function _acceptFundsFor(
    address token,
    uint256 amount,
    JBSingleAllowance memory allowance
)
    internal
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token being accepted.|
|`amount`|`uint256`|The number of tokens being accepted.|
|`allowance`|`JBSingleAllowance`|The permit2 context.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|amount The number of tokens which have been accepted.|


### _beforeTransferTo

Logic to be triggered before transferring tokens from this contract.


```solidity
function _beforeTransferTo(address to, address token, uint256 amount) internal returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|The address the transfer is going to.|
|`token`|`address`|The token being transferred.|
|`amount`|`uint256`|The number of tokens being transferred, as a fixed point number with the same number of decimals as the token specifies.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|payValue The value to attach to the transaction being sent.|


### _repayLoan

Pays down a loan.


```solidity
function _repayLoan(
    uint256 loanId,
    REVLoan storage loan,
    uint256 revnetId,
    uint256 repayBorrowAmount,
    uint256 sourceFeeAmount,
    uint256 collateralCountToReturn,
    address payable beneficiary
)
    internal
    returns (uint256, REVLoan memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The ID of the loan being paid down.|
|`loan`|`REVLoan`|The loan being paid down.|
|`revnetId`|`uint256`||
|`repayBorrowAmount`|`uint256`|The amount being paid down from the loan, denominated in the token of the source's accounting context.|
|`sourceFeeAmount`|`uint256`|The amount of the fee being taken from the revnet acting as the source of the loan.|
|`collateralCountToReturn`|`uint256`|The amount of collateral being returned that the loan no longer requires.|
|`beneficiary`|`address payable`|The address receiving the returned collateral and any tokens resulting from paying fees.|


### _reallocateCollateralFromLoan

Reallocates collateral from a loan by making a new loan based on the original, with reduced collateral.


```solidity
function _reallocateCollateralFromLoan(
    uint256 loanId,
    uint256 revnetId,
    uint256 collateralCountToRemove
)
    internal
    returns (uint256 reallocatedLoanId, REVLoan storage reallocatedLoan);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loanId`|`uint256`|The ID of the loan to reallocate collateral from.|
|`revnetId`|`uint256`|The ID of the revnet the loan is from.|
|`collateralCountToRemove`|`uint256`|The amount of collateral to remove from the loan.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`reallocatedLoanId`|`uint256`|The ID of the loan.|
|`reallocatedLoan`|`REVLoan`|The reallocated loan.|


### _removeFrom

Pays off a loan.


```solidity
function _removeFrom(REVLoan memory loan, uint256 revnetId, uint256 repaidBorrowAmount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`loan`|`REVLoan`|The loan being paid off.|
|`revnetId`|`uint256`|The ID of the revnet the loan is being paid off in.|
|`repaidBorrowAmount`|`uint256`|The amount being paid off, denominated in the token of the source's accounting context.|


### _returnCollateralFrom

Returns collateral from a loan.


```solidity
function _returnCollateralFrom(uint256 revnetId, uint256 collateralCount, address payable beneficiary) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revnetId`|`uint256`|The ID of the revnet the loan is being returned in.|
|`collateralCount`|`uint256`|The amount of collateral being returned from the loan.|
|`beneficiary`|`address payable`|The address receiving the returned collateral.|


### _transferFrom

Transfers tokens.


```solidity
function _transferFrom(address from, address payable to, address token, uint256 amount) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|The address to transfer tokens from.|
|`to`|`address payable`|The address to transfer tokens to.|
|`token`|`address`|The address of the token being transfered.|
|`amount`|`uint256`|The amount of tokens to transfer, as a fixed point number with the same number of decimals as the token.|


### fallback


```solidity
fallback() external payable;
```

### receive


```solidity
receive() external payable;
```

## Errors
### REVLoans_CollateralExceedsLoan

```solidity
error REVLoans_CollateralExceedsLoan(uint256 collateralToReturn, uint256 loanCollateral);
```

### REVLoans_InvalidPrepaidFeePercent

```solidity
error REVLoans_InvalidPrepaidFeePercent(uint256 prepaidFeePercent, uint256 min, uint256 max);
```

### REVLoans_NotEnoughCollateral

```solidity
error REVLoans_NotEnoughCollateral();
```

### REVLoans_OverflowAlert

```solidity
error REVLoans_OverflowAlert(uint256 value, uint256 limit);
```

### REVLoans_OverMaxRepayBorrowAmount

```solidity
error REVLoans_OverMaxRepayBorrowAmount(uint256 maxRepayBorrowAmount, uint256 repayBorrowAmount);
```

### REVLoans_PermitAllowanceNotEnough

```solidity
error REVLoans_PermitAllowanceNotEnough(uint256 allowanceAmount, uint256 requiredAmount);
```

### REVLoans_NewBorrowAmountGreaterThanLoanAmount

```solidity
error REVLoans_NewBorrowAmountGreaterThanLoanAmount(uint256 newBorrowAmount, uint256 loanAmount);
```

### REVLoans_NoMsgValueAllowed

```solidity
error REVLoans_NoMsgValueAllowed();
```

### REVLoans_LoanExpired

```solidity
error REVLoans_LoanExpired(uint256 timeSinceLoanCreated, uint256 loanLiquidationDuration);
```

### REVLoans_ReallocatingMoreCollateralThanBorrowedAmountAllows

```solidity
error REVLoans_ReallocatingMoreCollateralThanBorrowedAmountAllows(uint256 newBorrowAmount, uint256 loanAmount);
```

### REVLoans_RevnetsMismatch

```solidity
error REVLoans_RevnetsMismatch(address revnetOwner, address revnets);
```

### REVLoans_Unauthorized

```solidity
error REVLoans_Unauthorized(address caller, address owner);
```

### REVLoans_UnderMinBorrowAmount

```solidity
error REVLoans_UnderMinBorrowAmount(uint256 minBorrowAmount, uint256 borrowAmount);
```

### REVLoans_ZeroCollateralLoanIsInvalid

```solidity
error REVLoans_ZeroCollateralLoanIsInvalid();
```

