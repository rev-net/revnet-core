# Revnet

This repo provides tools for deploying Revnets: Retailistic networks, using the Juicebox and Uniswap protocols for its implementation.

For a Retailism TLDR, see https://jango.eth.limo/9E01E72C-6028-48B7-AD04-F25393307132/.

For more Retailism information, see:

A Retailistic View on CAC and LTV
https://jango.eth.limo/572BD957-0331-4977-8B2D-35F84D693276/

Modeling Retailism
https://jango.eth.limo/B762F3CC-AEFE-4DE0-B08C-7C16400AF718/

Retailism for Devs, Investors, and Customers 
https://jango.eth.limo/3EB05292-0376-4B7D-AFCF-042B70673C3D/

Observations: Network dynamics similar between atoms, cells, organisms, groups, dance parties.
https://jango.eth.limo/CF40F5D2-7BFE-43A3-9C15-1C6547FBD15C/

Join the conversation here: https://discord.gg/nT3XqbzNEr

In this repo, you'll find:
- a basic revnet design implemented in `BasicRevnetDeployer`.
- a design that accepts other pay hooks implemented in `PayHookRevnetDeployer`, which accepts other pay hooks that'll get used throughout the revnet's lifetime as it receives payments.
- a design that supports tiered 721 pay hooks implemented in `Tiered721RevnetDeployer`, which accepts data to deploy a tiered 721 pay hook that'll get used throughout the network's lifetime as people pay in, alongside other pay hooks that may also be specified.
- a design supports croptop, implemented in `CroptopRevnetDeployer`, which accepts data to deploy a tiered 721 pay hook that'll get used throughout the project's lifetime as people pay in that can also be posted to by the public through the croptop publisher contract. See https://croptop.eth.limo for more context.

You can use these contracts to deploy treasuries from etherscan, or wherever else they've been exposed from.

## Install

For `npm` projects (recommended):

```bash
npm install @bananapus/721-hook
```

For `forge` projects (not recommended):

```bash
forge install Bananapus/nana-721-hook
```

Add `@bananapus/721-hook/=lib/nana-721-hook/` to `remappings.txt`. You'll also need to install `nana-721-hook`'s dependencies and add similar remappings for them.

## Develop

`nana-721-hook` uses [npm](https://www.npmjs.com/) for package management and the [Foundry](https://github.com/foundry-rs/foundry) development toolchain for builds, tests, and deployments. To get set up, [install Node.js](https://nodejs.org/en/download) and install [Foundry](https://github.com/foundry-rs/foundry):

```bash
curl -L https://foundry.paradigm.xyz | sh
```

You can download and install dependencies with:

```bash
npm install && forge install
```

If you run into trouble with `forge install`, try using `git submodule update --init --recursive` to ensure that nested submodules have been properly initialized.

Some useful commands:

| Command               | Description                                         |
| --------------------- | --------------------------------------------------- |
| `forge build`         | Compile the contracts and write artifacts to `out`. |
| `forge fmt`           | Lint.                                               |
| `forge test`          | Run the tests.                                      |
| `forge build --sizes` | Get contract sizes.                                 |
| `forge coverage`      | Generate a test coverage report.                    |
| `foundryup`           | Update foundry. Run this periodically.              |
| `forge clean`         | Remove the build artifacts and cache directories.   |

To learn more, visit the [Foundry Book](https://book.getfoundry.sh/) docs.

## Scripts

For convenience, several utility commands are available in `package.json`.

| Command                           | Description                            |
| --------------------------------- | -------------------------------------- |
| `npm test`                        | Run local tests.                       |
| `npm run coverage:lcov`           | Generate an LCOV test coverage report. |
| `npm run deploy:ethereum-mainnet` | Deploy to Ethereum mainnet             |
| `npm run deploy:ethereum-sepolia` | Deploy to Ethereum Sepolia testnet     |
| `npm run deploy:optimism-mainnet` | Deploy to Optimism mainnet             |
| `npm run deploy:optimism-testnet` | Deploy to Optimism testnet             |