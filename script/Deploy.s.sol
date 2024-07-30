// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "@croptop/core/script/helpers/CroptopDeploymentLib.sol";
import "@bananapus/swap-terminal/script/helpers/SwapTerminalDeploymentLib.sol";
import "@bananapus/buyback-hook/script/helpers/BuybackDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import "./../src/REVBasicDeployer.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {REVStageConfig, REVMintConfig} from "../src/structs/REVStageConfig.sol";
import {REVLoanSource} from "../src/structs/REVLoanSource.sol";
import {REVDescription} from "../src/structs/REVDescription.sol";
import {REVBuybackPoolConfig} from "../src/structs/REVBuybackPoolConfig.sol";
import {IREVLoans} from "./../src/interfaces/IREVLoans.sol";
import {REVTiered721HookDeployer} from "./../src/REVTiered721HookDeployer.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";
import {REVCroptopDeployer} from "./../src/REVCroptopDeployer.sol";

struct FeeProjectConfig {
    REVConfig configuration;
    JBTerminalConfig[] terminalConfigurations;
    REVBuybackHookConfig buybackHookConfiguration;
    REVSuckerDeploymentConfig suckerDeploymentConfiguration;
}

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;
    /// @notice tracks the deployment of the croptop contracts for the chain we are deploying to.
    CroptopDeployment croptop;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deployment of the buyback hook.
    BuybackDeployment buybackHook;
    /// @notice tracks the deployment of the swap terminal.
    SwapTerminalDeployment swapTerminal;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 BASIC_DEPLOYER = "REVBasicDeployer";
    bytes32 NFT_HOOK_DEPLOYER = "REVTiered721HookDeployer";
    bytes32 CROPTOP_DEPLOYER = "REVCroptopDeployer";

    address OPERATOR = address(this);
    bytes32 ERC20_SALT = "REV_TOKEN";

    function configureSphinx() public override {
        // TODO: Update to contain revnet devs.
        sphinxConfig.projectName = "revnet-core-testnet";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        // Get the deployment addresses for the suckers contracts for this chain.
        suckers = SuckerDeploymentLib.getDeployment(
            vm.envOr("NANA_SUCKERS_DEPLOYMENT_PATH", string("node_modules/@bananapus/suckers/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        croptop = CroptopDeploymentLib.getDeployment(
            vm.envOr("CROPTOP_CORE_DEPLOYMENT_PATH", string("node_modules/@croptop/core/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        hook = Hook721DeploymentLib.getDeployment(
            vm.envOr("NANA_721_DEPLOYMENT_PATH", string("node_modules/@bananapus/721-hook/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        swapTerminal = SwapTerminalDeploymentLib.getDeployment(
            vm.envOr("NANA_SWAP_TERMINAL_DEPLOYMENT_PATH", string("node_modules/@bananapus/swap-terminal/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        buybackHook = BuybackDeploymentLib.getDeployment(
            vm.envOr("NANA_BUYBACK_HOOK_DEPLOYMENT_PATH", string("node_modules/@bananapus/buyback-hook/deployments/"))
        );

        // Since Juicebox has logic dependent on the timestamp we warp time to create a scenario closer to production.
        // We force simulations to make the assumption that the `START_TIME` has not occured,
        // and is not the current time.
        // Because of the cross-chain allowing components of nana-core, all chains require the same start_time,
        // for this reason we can't rely on the simulations block.time and we need a shared timestamp across all
        // simulations.
        uint256 _realTimestamp = vm.envUint("START_TIME");
        if (_realTimestamp <= block.timestamp - 1 days) {
            revert("Something went wrong while setting the 'START_TIME' environment variable.");
        }

        vm.warp(_realTimestamp);

        // Perform the deployment transactions.
        deploy();
    }

    function getFeeProjectConfig() internal view returns (FeeProjectConfig memory) {
        // Define constants
        string memory name = "Revnet";
        string memory symbol = "$REV";
        string memory projectUri = "ipfs://QmNRHT91HcDgMcenebYX7rJigt77cgNcosvuhX21wkF3tx";
        uint8 decimals = 18;
        uint256 decimalMultiplier = 10 ** decimals;

        // The tokens that the project accepts and stores.
        JBAccountingContext[] memory accountingContextsToAccept = new JBAccountingContext[](1);

        // Accept the chain's native currency through the multi terminal.
        accountingContextsToAccept[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        // The terminals that the project will accept funds through.
        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](2);
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: core.terminal, accountingContextsToAccept: accountingContextsToAccept});
        terminalConfigurations[1] = JBTerminalConfig({
            terminal: swapTerminal.swap_terminal,
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        // The project's revnet stage configurations.
        REVStageConfig[] memory stageConfigurations = new REVStageConfig[](3);

        {
            REVMintConfig[] memory mintConfs = new REVMintConfig[](1);
            mintConfs[0] = REVMintConfig({
                chainId: uint32(block.chainid),
                count: uint104(70_000 * decimalMultiplier),
                beneficiary: OPERATOR
            });

            stageConfigurations[0] = REVStageConfig({
                startsAtOrAfter: uint40(block.timestamp),
                mintConfigs: mintConfs,
                splitPercent: 2000, // 20%
                initialIssuance: uint112(1000 * decimalMultiplier),
                issuanceDecayFrequency: 90 days,
                issuanceDecayPercent: JBConstants.MAX_DECAY_PERCENT / 2,
                cashOutTaxRate: 6000 // 0.6
            });
        }

        stageConfigurations[1] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[0].startsAtOrAfter + 720 days),
            mintConfigs: new REVMintConfig[](0),
            splitPercent: 2000, // 20%
            initialIssuance: 0, // inherit from previous cycle.
            issuanceDecayFrequency: 180 days,
            issuanceDecayPercent: JBConstants.MAX_DECAY_PERCENT / 2,
            cashOutTaxRate: 6000 // 0.6
        });

        stageConfigurations[2] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[1].startsAtOrAfter + (20 * 365 days)),
            mintConfigs: new REVMintConfig[](0),
            splitPercent: 0,
            initialIssuance: 1, // this is a special number that is as close to max price as we can get.
            issuanceDecayFrequency: 0,
            issuanceDecayPercent: 0,
            cashOutTaxRate: 6000 // 0.6
        });

        // The project's revnet configuration
        REVConfig memory revnetConfiguration = REVConfig({
            description: REVDescription(name, symbol, projectUri, ERC20_SALT),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: OPERATOR,
            stageConfigurations: stageConfigurations,
            loanSources: new REVLoanSource[](0)
        });

        // The project's buyback hook configuration.
        REVBuybackPoolConfig[] memory buybackPoolConfigurations = new REVBuybackPoolConfig[](1);
        buybackPoolConfigurations[0] = REVBuybackPoolConfig({
            token: JBConstants.NATIVE_TOKEN,
            fee: 10_000,
            twapWindow: 2 days,
            twapSlippageTolerance: 9000
        });
        REVBuybackHookConfig memory buybackHookConfiguration =
            REVBuybackHookConfig({hook: buybackHook.hook, poolConfigurations: buybackPoolConfigurations});

        return FeeProjectConfig({
            configuration: revnetConfiguration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: REVSuckerDeploymentConfig({
                deployerConfigurations: new JBSuckerDeployerConfig[](0),
                salt: keccak256(abi.encodePacked("REV"))
            })
        });
    }

    function deploy() public sphinx {
        // TODO figure out how to reference project ID if the contracts are already deployed.
        uint256 FEE_PROJECT_ID = core.projects.createFor(safeAddress());

        // Check if the contracts are already deployed or if there are any changes.
        if (
            !_isDeployed(
                BASIC_DEPLOYER,
                type(REVBasicDeployer).creationCode,
                abi.encode(core.controller, suckers.registry, FEE_PROJECT_ID)
            )
        ) {
            REVBasicDeployer _basicDeployer = new REVBasicDeployer{salt: BASIC_DEPLOYER}(
                core.controller, suckers.registry, IREVLoans(address(0)), FEE_PROJECT_ID
            );

            // Approve the basic deployer to configure the project.
            core.projects.approve(address(_basicDeployer), FEE_PROJECT_ID);

            // Build the config.
            FeeProjectConfig memory feeProjectConfig = getFeeProjectConfig();

            // Configure the project.
            _basicDeployer.deployFor({
                revnetId: FEE_PROJECT_ID,
                configuration: feeProjectConfig.configuration,
                terminalConfigurations: feeProjectConfig.terminalConfigurations,
                buybackHookConfiguration: feeProjectConfig.buybackHookConfiguration,
                suckerDeploymentConfiguration: feeProjectConfig.suckerDeploymentConfiguration
            });
        }

        if (
            !_isDeployed(
                NFT_HOOK_DEPLOYER,
                type(REVTiered721HookDeployer).creationCode,
                abi.encode(core.controller, suckers.registry, IREVLoans(address(0)), FEE_PROJECT_ID, hook.hook_deployer)
            )
        ) {
            new REVTiered721HookDeployer{salt: NFT_HOOK_DEPLOYER}(
                core.controller, suckers.registry, IREVLoans(address(0)), FEE_PROJECT_ID, hook.hook_deployer
            );
        }

        if (
            !_isDeployed(
                CROPTOP_DEPLOYER,
                type(REVCroptopDeployer).creationCode,
                abi.encode(
                    core.controller,
                    suckers.registry,
                    IREVLoans(address(0)),
                    FEE_PROJECT_ID,
                    hook.hook_deployer,
                    croptop.publisher
                )
            )
        ) {
            new REVCroptopDeployer{salt: CROPTOP_DEPLOYER}(
                core.controller,
                suckers.registry,
                IREVLoans(address(0)),
                FEE_PROJECT_ID,
                hook.hook_deployer,
                croptop.publisher
            );
        }

        // TODO get a reference to the $REV revnet specifications that will be set.
        // core.projects.transferOwnership(FEE_PROJECT_ID);
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return address(_deployedTo).code.length != 0;
    }
}
