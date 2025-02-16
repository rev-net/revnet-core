# REVBuybackHookConfig
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/structs/REVBuybackHookConfig.sol)

**Notes:**
- member: hook The buyback hook to use.

- member: poolConfigurations The pools to setup on the given buyback contract.


```solidity
struct REVBuybackHookConfig {
    IJBBuybackHook hook;
    REVBuybackPoolConfig[] poolConfigurations;
}
```

