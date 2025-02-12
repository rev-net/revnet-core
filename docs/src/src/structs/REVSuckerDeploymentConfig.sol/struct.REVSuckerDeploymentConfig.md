# REVSuckerDeploymentConfig
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/structs/REVSuckerDeploymentConfig.sol)

**Notes:**
- member: deployerConfigurations The information for how to suck tokens to other chains.

- member: salt The salt to use for creating suckers so that they use the same address across chains.


```solidity
struct REVSuckerDeploymentConfig {
    JBSuckerDeployerConfig[] deployerConfigurations;
    bytes32 salt;
}
```

