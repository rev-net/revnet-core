# REVConfig
[Git Source](https://github.com/rev-net/revnet-core/blob/4ce5b6e07a0e5ba0e8d652f2e9efcc8c2d12b8d1/src/structs/REVConfig.sol)

**Notes:**
- member: description The description of the revnet.

- member: baseCurrency The currency that the issuance is based on.

- member: premintTokenAmount The number of tokens that should be preminted to the initial operator.

- member: premintChainId The ID of the chain on which the premint should be honored.

- member: premintStage The stage during which the premint should be honored.

- member: splitOperator The address that will receive the token premint and initial production split,
and who is allowed to change who the operator is. Only the operator can replace itself after deployment.

- member: stageConfigurations The periods of changing constraints.

- member: loanSources The sources for loans.

- member: loans The loans contract, which can mint the revnet's tokens and use the revnet's balance.


```solidity
struct REVConfig {
    REVDescription description;
    uint32 baseCurrency;
    address splitOperator;
    REVStageConfig[] stageConfigurations;
    REVLoanSource[] loanSources;
    address loans;
}
```

