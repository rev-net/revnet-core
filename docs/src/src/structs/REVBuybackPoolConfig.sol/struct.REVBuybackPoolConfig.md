# REVBuybackPoolConfig
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/structs/REVBuybackPoolConfig.sol)

**Notes:**
- member: token The token to setup a pool for.

- member: poolFee The fee of the pool in which swaps occur when seeking the best price for a new participant.
This incentivizes liquidity providers. Out of 1_000_000. A common value is 1%, or 10_000. Other passible values are
0.3% and 0.1%.

- member: twapWindow The time window to take into account when quoting a price based on TWAP.

- member: twapSlippageTolerance The pricetolerance to accept when quoting a price based on TWAP.


```solidity
struct REVBuybackPoolConfig {
    address token;
    uint24 fee;
    uint32 twapWindow;
    uint32 twapSlippageTolerance;
}
```

