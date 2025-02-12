# REVLoanSource
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/structs/REVLoanSource.sol)

**Notes:**
- member: token The token that is being loaned.

- member: terminal The terminal that the loan is being made from.


```solidity
struct REVLoanSource {
    address token;
    IJBPayoutTerminal terminal;
}
```

