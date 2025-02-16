# IREVLoans
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/interfaces/IREVLoans.sol)


## Functions
### LOAN_LIQUIDATION_DURATION


```solidity
function LOAN_LIQUIDATION_DURATION() external view returns (uint256);
```

### PERMIT2


```solidity
function PERMIT2() external view returns (IPermit2);
```

### CONTROLLER


```solidity
function CONTROLLER() external view returns (IJBController);
```

### REVNETS


```solidity
function REVNETS() external view returns (IREVDeployer);
```

### DIRECTORY


```solidity
function DIRECTORY() external view returns (IJBDirectory);
```

### PRICES


```solidity
function PRICES() external view returns (IJBPrices);
```

### PROJECTS


```solidity
function PROJECTS() external view returns (IJBProjects);
```

### REV_ID


```solidity
function REV_ID() external view returns (uint256);
```

### REV_PREPAID_FEE_PERCENT


```solidity
function REV_PREPAID_FEE_PERCENT() external view returns (uint256);
```

### MIN_PREPAID_FEE_PERCENT


```solidity
function MIN_PREPAID_FEE_PERCENT() external view returns (uint256);
```

### MAX_PREPAID_FEE_PERCENT


```solidity
function MAX_PREPAID_FEE_PERCENT() external view returns (uint256);
```

### borrowableAmountFrom


```solidity
function borrowableAmountFrom(
    uint256 revnetId,
    uint256 collateral,
    uint256 decimals,
    uint256 currency
)
    external
    view
    returns (uint256);
```

### determineSourceFeeAmount


```solidity
function determineSourceFeeAmount(
    REVLoan memory loan,
    uint256 amount
)
    external
    view
    returns (uint256 sourceFeeAmount);
```

### isLoanSourceOf


```solidity
function isLoanSourceOf(uint256 revnetId, IJBPayoutTerminal terminal, address token) external view returns (bool);
```

### loanOf


```solidity
function loanOf(uint256 loanId) external view returns (REVLoan memory);
```

### loanSourcesOf


```solidity
function loanSourcesOf(uint256 revnetId) external view returns (REVLoanSource[] memory);
```

### numberOfLoansFor


```solidity
function numberOfLoansFor(uint256 revnetId) external view returns (uint256);
```

### revnetIdOfLoanWith


```solidity
function revnetIdOfLoanWith(uint256 loanId) external view returns (uint256);
```

### tokenUriResolver


```solidity
function tokenUriResolver() external view returns (IJBTokenUriResolver);
```

### totalBorrowedFrom


```solidity
function totalBorrowedFrom(
    uint256 revnetId,
    IJBPayoutTerminal terminal,
    address token
)
    external
    view
    returns (uint256);
```

### totalCollateralOf


```solidity
function totalCollateralOf(uint256 revnetId) external view returns (uint256);
```

### borrowFrom


```solidity
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
```

### liquidateExpiredLoansFrom


```solidity
function liquidateExpiredLoansFrom(uint256 revnetId, uint256 startingLoanId, uint256 count) external;
```

### repayLoan


```solidity
function repayLoan(
    uint256 loanId,
    uint256 maxRepayBorrowAmount,
    uint256 newCollateral,
    address payable beneficiary,
    JBSingleAllowance calldata allowance
)
    external
    payable
    returns (uint256 paidOffLoanId, REVLoan memory loan);
```

### reallocateCollateralFromLoan


```solidity
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
```

### setTokenUriResolver


```solidity
function setTokenUriResolver(IJBTokenUriResolver resolver) external;
```

## Events
### Borrow

```solidity
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
```

### Liquidate

```solidity
event Liquidate(uint256 indexed loanId, uint256 indexed revnetId, REVLoan loan, address caller);
```

### RepayLoan

```solidity
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
```

### ReallocateCollateral

```solidity
event ReallocateCollateral(
    uint256 indexed loanId,
    uint256 indexed revnetId,
    uint256 indexed reallocatedLoanId,
    REVLoan reallocatedLoan,
    uint256 removedcollateralCount,
    address caller
);
```

### SetTokenUriResolver

```solidity
event SetTokenUriResolver(IJBTokenUriResolver indexed resolver, address caller);
```

