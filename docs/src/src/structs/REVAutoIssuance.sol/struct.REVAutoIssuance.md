# REVAutoIssuance
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/structs/REVAutoIssuance.sol)

**Notes:**
- member: chainId The ID of the chain on which the mint should be honored.

- member: count The number of tokens that should be minted.

- member: beneficiary The address that will receive the minted tokens.


```solidity
struct REVAutoIssuance {
    uint32 chainId;
    uint104 count;
    address beneficiary;
}
```

