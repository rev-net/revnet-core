// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/buyback-hook/script/helpers/BuybackDeploymentLib.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "@bananapus/swap-terminal/script/helpers/SwapTerminalDeploymentLib.sol";
import "@croptop/core/script/helpers/CroptopDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core/src/libraries/JBCurrencyIds.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers/src/structs/JBTokenMapping.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IJBSplitHook} from "@bananapus/core/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";

import {REVDeployer} from "./../src/REVDeployer.sol";
import {REVAutoIssuance} from "../src/structs/REVAutoIssuance.sol";
import {REVBuybackHookConfig} from "../src/structs/REVBuybackHookConfig.sol";
import {REVConfig} from "../src/structs/REVConfig.sol";
import {REVDescription} from "../src/structs/REVDescription.sol";
import {REVLoanSource} from "../src/structs/REVLoanSource.sol";
import {REVBuybackPoolConfig} from "../src/structs/REVBuybackPoolConfig.sol";
import {REVStageConfig} from "../src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "../src/structs/REVSuckerDeploymentConfig.sol";
import {REVLoans, IREVLoans} from "./../src/REVLoans.sol";

struct FeeProjectConfig {
    REVConfig configuration;
    JBTerminalConfig[] terminalConfigurations;
    REVBuybackHookConfig buybackHookConfiguration;
    REVSuckerDeploymentConfig suckerDeploymentConfiguration;
}

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the buyback hook.
    BuybackDeployment buybackHook;
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the croptop contracts for the chain we are deploying to.
    CroptopDeployment croptop;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;
    /// @notice tracks the deployment of the swap terminal.
    SwapTerminalDeployment swapTerminal;

    uint32 PREMINT_CHAIN_ID = 11_155_111;
    string NAME = "Revnet";
    string SYMBOL = "REV";
    string PROJECT_URI = "ipfs://QmSiJhANtkySxt6eBDJS3E5RNJx3QXRNwz6XijdmEXw7JC";
    uint32 NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint32 ETH_CURRENCY = JBCurrencyIds.ETH;
    uint8 DECIMALS = 18;
    uint256 DECIMAL_MULTIPLIER = 10 ** DECIMALS;
    bytes32 ERC20_SALT = "_REV_ERC20_SALT_";
    bytes32 SUCKER_SALT = "_REV_SUCKER_SALT_";
    bytes32 DEPLOYER_SALT = "_REV_DEPLOYER_SALT_";
    bytes32 REVLOANS_SALT = "_REV_LOANS_SALT_";
    address LOANS_OWNER;
    address OPERATOR;
    uint256 TIME_UNTIL_START = 1 days;
    address TRUSTED_FORWARDER;
    IPermit2 PERMIT2;

    function configureSphinx() public override {
        // TODO: Update to contain revnet devs.
        sphinxConfig.projectName = "revnet-core-testnet";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the operator address.
        OPERATOR = safeAddress();
        // Get the loans owner address.
        LOANS_OWNER = safeAddress();

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

        // We use the same trusted forwarder and permit2 as the core deployment.
        TRUSTED_FORWARDER = core.controller.trustedForwarder();
        PERMIT2 = core.terminal.PERMIT2();

        // Since Juicebox has logic dependent on the timestamp we warp time to create a scenario closer to production.
        // We force simulations to make the assumption that the `START_TIME` has not occured,
        // and is not the current time.
        // Because of the cross-chain allowing components of nana-core, all chains require the same start_time,
        // for this reason we can't rely on the simulations block.time and we need a shared timestamp across all
        // simulations.
        uint256 _realTimestamp = vm.envUint("START_TIME");
        if (_realTimestamp <= block.timestamp - TIME_UNTIL_START) {
            revert("Something went wrong while setting the 'START_TIME' environment variable.");
        }

        vm.warp(_realTimestamp);

        // Perform the deployment transactions.
        deploy();
    }

    function getFeeProjectConfig(IREVLoans revloans) internal view returns (FeeProjectConfig memory) {
        // The tokens that the project accepts and stores.
        JBAccountingContext[] memory accountingContextsToAccept = new JBAccountingContext[](1);

        // Accept the chain's native currency through the multi terminal.
        accountingContextsToAccept[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        // The terminals that the project will accept funds through.
        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](2);
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: core.terminal, accountingContextsToAccept: accountingContextsToAccept});
        terminalConfigurations[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(swapTerminal.swap_terminal)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        // The project's revnet stage configurations.
        REVStageConfig[] memory stageConfigurations = new REVStageConfig[](3);

        // Create a split group that assigns all of the splits to the operator.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(OPERATOR),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        {
            REVAutoIssuance[] memory issuanceConfs = new REVAutoIssuance[](1);
            issuanceConfs[0] = REVAutoIssuance({
                chainId: PREMINT_CHAIN_ID,
                count: uint104(775_000 * DECIMAL_MULTIPLIER),
                beneficiary: OPERATOR
            });

            stageConfigurations[0] = REVStageConfig({
                startsAtOrAfter: uint40(block.timestamp + TIME_UNTIL_START),
                autoIssuances: issuanceConfs,
                splitPercent: 3800, // 38%
                splits: splits,
                initialIssuance: uint112(10_000 * DECIMAL_MULTIPLIER),
                issuanceCutFrequency: 90 days,
                issuanceCutPercent: 380_000_000, // 38%
                cashOutTaxRate: 1000, // 0.1
                extraMetadata: 4 // Allow adding suckers.
            });
        }

        {
            REVAutoIssuance[] memory issuanceConfs = new REVAutoIssuance[](1);
            issuanceConfs[0] = REVAutoIssuance({
                chainId: PREMINT_CHAIN_ID,
                count: uint104(1_550_000 * DECIMAL_MULTIPLIER),
                beneficiary: OPERATOR
            });

            stageConfigurations[1] = REVStageConfig({
                startsAtOrAfter: uint40(stageConfigurations[0].startsAtOrAfter + 720 days),
                autoIssuances: issuanceConfs,
                splitPercent: 3800, // 38%
                splits: splits,
                initialIssuance: 1, // inherit from previous cycle.
                issuanceCutFrequency: 30 days,
                issuanceCutPercent: 70_000_000, // 7%
                cashOutTaxRate: 1000, // 0.1
                extraMetadata: 4 // Allow adding suckers.
            });
        }

        stageConfigurations[2] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[1].startsAtOrAfter + (3600 days)),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 3800, // 38%
            splits: splits,
            initialIssuance: 0, // no more issaunce.
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 1000, // 0.1
            extraMetadata: 4 // Allow adding suckers.
        });

        REVConfig memory revnetConfiguration;
        {
            // Thr projects loan configuration.
            REVLoanSource[] memory loanSources = new REVLoanSource[](1);
            loanSources[0] = REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: core.terminal});

            // The project's revnet configuration
            revnetConfiguration = REVConfig({
                description: REVDescription(NAME, SYMBOL, PROJECT_URI, ERC20_SALT),
                baseCurrency: ETH_CURRENCY,
                splitOperator: OPERATOR,
                stageConfigurations: stageConfigurations,
                loanSources: loanSources,
                loans: address(revloans)
            });
        }

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

        // Organize the instructions for how this project will connect to other chains.
        JBTokenMapping[] memory tokenMappings = new JBTokenMapping[](1);
        tokenMappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            remoteToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            minBridgeAmount: 0.01 ether
        });

        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration;

        {
            JBSuckerDeployerConfig[] memory suckerDeployerConfigurations;
            if (block.chainid == 1 || block.chainid == 11_155_111) {
                suckerDeployerConfigurations = new JBSuckerDeployerConfig[](3);
                // OP
                suckerDeployerConfigurations[0] =
                    JBSuckerDeployerConfig({deployer: suckers.optimismDeployer, mappings: tokenMappings});

                suckerDeployerConfigurations[1] =
                    JBSuckerDeployerConfig({deployer: suckers.baseDeployer, mappings: tokenMappings});

                suckerDeployerConfigurations[2] =
                    JBSuckerDeployerConfig({deployer: suckers.arbitrumDeployer, mappings: tokenMappings});
            } else {
                suckerDeployerConfigurations = new JBSuckerDeployerConfig[](1);
                // L2 -> Mainnet
                suckerDeployerConfigurations[0] = JBSuckerDeployerConfig({
                    deployer: address(suckers.optimismDeployer) != address(0)
                        ? suckers.optimismDeployer
                        : address(suckers.baseDeployer) != address(0) ? suckers.baseDeployer : suckers.arbitrumDeployer,
                    mappings: tokenMappings
                });

                if (address(suckerDeployerConfigurations[0].deployer) == address(0)) {
                    revert("L2 > L1 Sucker is not configured");
                }
            }
            // Specify all sucker deployments.
            suckerDeploymentConfiguration =
                REVSuckerDeploymentConfig({deployerConfigurations: suckerDeployerConfigurations, salt: SUCKER_SALT});
        }

        return FeeProjectConfig({
            configuration: revnetConfiguration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });
    }

    function deploy() public sphinx {
        // TODO figure out how to reference project ID if the contracts are already deployed.
        uint256 FEE_PROJECT_ID = core.projects.createFor(safeAddress());

        REVDeployer _basicDeployer;
        {
            // Check if the contracts are already deployed or if there are any changes.
            (address _deployer, bool _revDeployerIsDeployed) = _isDeployed(
                DEPLOYER_SALT,
                type(REVDeployer).creationCode,
                abi.encode(core.controller, suckers.registry, FEE_PROJECT_ID, hook.hook_deployer, croptop.publisher)
            );

            _basicDeployer = !_revDeployerIsDeployed
                ? new REVDeployer{salt: DEPLOYER_SALT}(
                    core.controller,
                    suckers.registry,
                    FEE_PROJECT_ID,
                    hook.hook_deployer,
                    croptop.publisher,
                    TRUSTED_FORWARDER
                )
                : REVDeployer(payable(_deployer));
        }
        // Deploy revloans if its not deployed yet.
        REVLoans revloans;
        {
            (address _revloans, bool _revloansIsDeployed) = _isDeployed(
                REVLOANS_SALT,
                type(REVLoans).creationCode,
                abi.encode(_basicDeployer, FEE_PROJECT_ID, PERMIT2, TRUSTED_FORWARDER)
            );

            revloans = !_revloansIsDeployed
                ? new REVLoans{salt: REVLOANS_SALT}({
                    revnets: _basicDeployer,
                    revId: FEE_PROJECT_ID,
                    owner: LOANS_OWNER,
                    permit2: PERMIT2,
                    trustedForwarder: TRUSTED_FORWARDER
                })
                : REVLoans(payable(_revloans));
        }

        // Approve the basic deployer to configure the project.
        core.projects.approve(address(_basicDeployer), FEE_PROJECT_ID);

        // Build the config.
        FeeProjectConfig memory feeProjectConfig = getFeeProjectConfig(revloans);

        // Configure the project.
        _basicDeployer.deployFor({
            revnetId: FEE_PROJECT_ID,
            configuration: feeProjectConfig.configuration,
            terminalConfigurations: feeProjectConfig.terminalConfigurations,
            buybackHookConfiguration: feeProjectConfig.buybackHookConfiguration,
            suckerDeploymentConfiguration: feeProjectConfig.suckerDeploymentConfiguration
        });
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address deployedTo, bool isDeployed)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return (_deployedTo, address(_deployedTo).code.length != 0);
    }
}
