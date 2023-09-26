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

# Dev

## Prerequisites
### Install & Update Foundry
Install Forge with `curl -L https://foundry.paradigm.xyz | bash`. If you already have Foundry installed, run `foundryup` to update to the latest version. More detailed instructions can be found in the [Foundry Book](https://book.getfoundry.sh/getting-started/installation).

### Install & Update Yarn
Follow the instructions in the [Yarn Docs](https://classic.yarnpkg.com/en/docs/install). People tend to use the latest version of Yarn 1 (not Yarn 2+).

## Install Included Dependencies
Install dependencies (forge tests, Juice-contracts-V3, OZ) via `yarn install` (the `preinstall` script will run `forge install` for you)

# Adding dependencies
## With Yarn
If the dependency you would like to install has an NPM package, use `yarn add [package]` where [package] is the package name. This will install the dependency to `node_modules`.

Tell forge to look for node libraries by adding `node_modules` to the `foundry.toml` by updating `libs` like so: `libs = ['lib', 'node_modules']`.

Add dependencies to `remappings.txt` by running `forge remappings >> remappings.txt`. For example, the NPM package `jbx-protocol` is remapped as `@jbx-protocol/=node_modules/@jbx-protocol/`.

## With Forge
If the dependency you would like to install does not have an up-to-date NPM package, use `forge install [dependency]` where [dependency] is the path to the dependency repo. This will install the dependency to `/lib`. Forge manages dependencies using git submodules.

Run `forge remappings > remappings.txt` to write the dependencies to `remappings.txt`. Note that this will overwrite that file. 

If nested dependencies are not installing, try this workaround `git submodule update --init --recursive --force`. Nested dependencies are dependencies of the dependencies you have installed. 

More information on remappings is available in the Forge Book.

# Updating dependencies
## With Yarn
Run `yarn upgrade [package]`.

## With Forge
Run `foundryup` to update forge. 

Run `forge update` to update all dependencies, or run `forge update [dependency]` to update a specific dependency.

# Usage
use `yarn test` to run tests

use `yarn test:fork` to run tests in CI mode (including slower mainnet fork tests)

use `yarn size` to check contract size

use `yarn doc` to generate natspec docs

use `yarn lint` to lint the code

use `yarn tree` to generate a Solidity dependency tree

use `yarn deploy:mainnet` and `yarn deploy:goerli` to deploy and verify (see .env.example for required env vars, using a ledger by default).

## Code coverage
Run `yarn coverage`to display code coverage summary and generate an LCOV report

To display code coverage in VSCode:
- You need to install the [coverage gutters extension (Ryan Luker)](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) or any other extension handling LCOV reports
- ctrl shift p > "Coverage Gutters: Display Coverage" (coverage are the colored markdown lines in the left gutter, after the line numbers)

## PR
Github CI flow will run both unit and forked tests, log the contracts size (with the tests) and check linting compliance.
