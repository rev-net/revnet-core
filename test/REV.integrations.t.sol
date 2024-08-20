// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core/test/helpers/TestBaseWorkflow.sol";
import /* {*} from "@bananapus/721-hook/src/JB721TiersHookDeployer.sol";
    import /* {*} from */ "./../src/REVDeployer.sol";
import "@croptop/core/src/CTPublisher.sol";

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "@croptop/core/script/helpers/CroptopDeploymentLib.sol";
import "@bananapus/swap-terminal/script/helpers/SwapTerminalDeploymentLib.sol";
import "@bananapus/buyback-hook/script/helpers/BuybackDeploymentLib.sol";

import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {REVLoans} from "../src/REVLoans.sol";
import {REVStageConfig, REVAutoMint} from "../src/structs/REVStageConfig.sol";
import {REVLoanSource} from "../src/structs/REVLoanSource.sol";
import {REVDescription} from "../src/structs/REVDescription.sol";
import {REVBuybackPoolConfig} from "../src/structs/REVBuybackPoolConfig.sol";
import {IREVLoans} from "./../src/interfaces/IREVLoans.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";
import {JBSuckerRegistry} from "@bananapus/suckers/src/JBSuckerRegistry.sol";
import {JBTokenMapping} from "@bananapus/suckers/src/structs/JBTokenMapping.sol";
import {JB721TiersHookDeployer} from "@bananapus/721-hook/src/JB721TiersHookDeployer.sol";
import {JBArbitrumSuckerDeployer} from "@bananapus/suckers/src/deployers/JBArbitrumSuckerDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook/src/JB721TiersHookStore.sol";
import {JBAddressRegistry} from "@bananapus/address-registry/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry/src/interfaces/IJBAddressRegistry.sol";

struct FeeProjectConfig {
    REVConfig configuration;
    JBTerminalConfig[] terminalConfigurations;
    REVBuybackHookConfig buybackHookConfiguration;
    REVSuckerDeploymentConfig suckerDeploymentConfiguration;
}

contract REVnet_Integrations is TestBaseWorkflow, JBTest {
    /// @notice the salts that are used to deploy the contracts.
    bytes32 BASIC_DEPLOYER_SALT = "REVDeployer";
    bytes32 ERC20_SALT = "REV_TOKEN";

    REVDeployer BASIC_DEPLOYER;
    JB721TiersHook EXAMPLE_HOOK;

    /// @notice Deploys tiered ERC-721 hooks for revnets.
    IJB721TiersHookDeployer HOOK_DEPLOYER;
    IJB721TiersHookStore HOOK_STORE;
    IJBAddressRegistry ADDRESS_REGISTRY;

    IREVLoans LOANS_CONTRACT;

    /// @notice Deploys and tracks suckers for revnets.
    IJBSuckerRegistry SUCKER_REGISTRY;
    IJBSuckerDeployer ARB_SUCKER_DEPLOYER;
    bytes ENCODED_CONFIG;

    CTPublisher PUBLISHER;

    uint256 FEE_PROJECT_ID;
    uint256 REVNET_ID;
    uint256 decimals = 18;
    uint256 decimalMultiplier = 10 ** decimals;

    uint256 firstStageId;

    address USER = makeAddr("user");

    function getFeeProjectConfig() internal returns (FeeProjectConfig memory) {
        // Define constants
        string memory name = "Revnet";
        string memory symbol = "$REV";
        string memory projectUri = "ipfs://QmNRHT91HcDgMcenebYX7rJigt77cgNcosvuhX21wkF3tx";

        // The tokens that the project accepts and stores.
        JBAccountingContext[] memory accountingContextsToAccept = new JBAccountingContext[](1);

        // Accept the chain's native currency through the multi terminal.
        accountingContextsToAccept[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        // The terminals that the project will accept funds through.
        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: accountingContextsToAccept});

        // The project's revnet stage configurations.
        REVStageConfig[] memory stageConfigurations = new REVStageConfig[](3);

        REVAutoMint[] memory mintConfs = new REVAutoMint[](1);
        mintConfs[0] = REVAutoMint({
            chainId: uint32(block.chainid),
            count: uint104(70_000 * decimalMultiplier),
            beneficiary: multisig()
        });

        {
            firstStageId = block.timestamp;

            stageConfigurations[0] = REVStageConfig({
                startsAtOrAfter: uint40(block.timestamp),
                autoMints: mintConfs,
                splitPercent: 2000, // 20%
                initialIssuance: uint112(1000 * decimalMultiplier),
                issuanceDecayFrequency: 90 days,
                issuanceDecayPercent: JBConstants.MAX_DECAY_PERCENT / 2,
                cashOutTaxRate: 6000, // 0.6
                extraMetadata: 0
            });
        }

        stageConfigurations[1] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[0].startsAtOrAfter + 720 days),
            autoMints: mintConfs,
            splitPercent: 2000, // 20%
            initialIssuance: 0, // inherit from previous cycle.
            issuanceDecayFrequency: 180 days,
            issuanceDecayPercent: JBConstants.MAX_DECAY_PERCENT / 2,
            cashOutTaxRate: 6000, // 0.6
            extraMetadata: 0
        });

        stageConfigurations[2] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[1].startsAtOrAfter + (20 * 365 days)),
            autoMints: new REVAutoMint[](0),
            splitPercent: 0,
            initialIssuance: 1, // this is a special number that is as close to max price as we can get.
            issuanceDecayFrequency: 0,
            issuanceDecayPercent: 0,
            cashOutTaxRate: 6000, // 0.6
            extraMetadata: 0
        });

        REVLoanSource[] memory _loanSources = new REVLoanSource[](0);

        // The project's revnet configuration
        REVConfig memory revnetConfiguration = REVConfig({
            description: REVDescription(name, symbol, projectUri, ERC20_SALT),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stageConfigurations,
            loanSources: _loanSources,
            loans: address(0),
            preventChainExtension: false
        });

        ENCODED_CONFIG = abi.encode(
            revnetConfiguration.baseCurrency,
            revnetConfiguration.loans,
            revnetConfiguration.preventChainExtension,
            revnetConfiguration.description.name,
            revnetConfiguration.description.ticker,
            revnetConfiguration.description.salt
        );

        // The project's buyback hook configuration.
        REVBuybackPoolConfig[] memory buybackPoolConfigurations = new REVBuybackPoolConfig[](1);
        buybackPoolConfigurations[0] = REVBuybackPoolConfig({
            token: JBConstants.NATIVE_TOKEN,
            fee: 10_000,
            twapWindow: 2 days,
            twapSlippageTolerance: 9000
        });
        REVBuybackHookConfig memory buybackHookConfiguration =
            REVBuybackHookConfig({hook: IJBBuybackHook(address(0)), poolConfigurations: buybackPoolConfigurations});

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

    function setUp() public override {
        super.setUp();

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbProjects(), jbPermissions(), multisig());

        EXAMPLE_HOOK = new JB721TiersHook(jbDirectory(), jbPermissions(), multisig());

        HOOK_STORE = new JB721TiersHookStore();

        ADDRESS_REGISTRY = new JBAddressRegistry();

        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());

        PUBLISHER = new CTPublisher(jbController(), jbPermissions(), FEE_PROJECT_ID, multisig());

        BASIC_DEPLOYER = new REVDeployer{salt: BASIC_DEPLOYER_SALT}(
            jbController(), SUCKER_REGISTRY, FEE_PROJECT_ID, HOOK_DEPLOYER, PUBLISHER
        );

        ARB_SUCKER_DEPLOYER = new JBArbitrumSuckerDeployer(jbDirectory(), jbTokens(), jbPermissions(), multisig());

        // Approve the basic deployer to configure the project.
        vm.startPrank(address(multisig()));
        jbProjects().approve(address(BASIC_DEPLOYER), FEE_PROJECT_ID);
        SUCKER_REGISTRY.allowSuckerDeployer(address(ARB_SUCKER_DEPLOYER));

        vm.stopPrank();

        // Build the config.
        FeeProjectConfig memory feeProjectConfig = getFeeProjectConfig();

        // Empty hook config.
        REVDeploy721TiersHookConfig memory tiered721HookConfiguration;

        // Configure the project.
        REVNET_ID = BASIC_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, // Zero to deploy a new revnet
            configuration: feeProjectConfig.configuration,
            terminalConfigurations: feeProjectConfig.terminalConfigurations,
            buybackHookConfiguration: feeProjectConfig.buybackHookConfiguration,
            suckerDeploymentConfiguration: feeProjectConfig.suckerDeploymentConfiguration
        });
    }

    function test_Is_Setup() public {
        assertGt(uint160(address(jbDirectory())), uint160(0));
        assertGt(FEE_PROJECT_ID, 0);
        assertGt(jbProjects().count(), 0);
        assertGt(REVNET_ID, 0);
    }

    function test_preMint() public {
        assertEq(70_000 * decimalMultiplier, IJBToken(jbTokens().tokenOf(REVNET_ID)).balanceOf(multisig()));
    }

    function test_realize_automint() public {
        uint256 perStageMintAmount = 70_000 * decimalMultiplier;

        assertEq(perStageMintAmount, IJBToken(jbTokens().tokenOf(REVNET_ID)).balanceOf(multisig()));

        vm.warp(firstStageId + 720 days);

        assertEq(perStageMintAmount, BASIC_DEPLOYER.unrealizedAutoMintAmountOf(REVNET_ID));

        vm.expectEmit();
        emit IREVDeployer.Mint(REVNET_ID, firstStageId + 1, multisig(), perStageMintAmount, address(this));
        BASIC_DEPLOYER.autoMintFor(REVNET_ID, firstStageId + 1, multisig());

        assertEq(perStageMintAmount * 2, IJBToken(jbTokens().tokenOf(REVNET_ID)).balanceOf(multisig()));
    }

    function test_change_split_operator() public {
        vm.prank(multisig());
        BASIC_DEPLOYER.setSplitOperatorOf(REVNET_ID, address(this));

        bool isNewOperator = BASIC_DEPLOYER.isSplitOperatorOf(REVNET_ID, address(this));

        assertEq(isNewOperator, true);
    }

    function test_sucker_deploy() public {
        JBSuckerDeployerConfig[] memory suckerDeployerConfig = new JBSuckerDeployerConfig[](1);

        JBTokenMapping[] memory tokenMapping = new JBTokenMapping[](1);

        tokenMapping[0] = JBTokenMapping({
            localToken: makeAddr("someToken"),
            minGas: 200_000,
            remoteToken: makeAddr("someOtherToken"),
            minBridgeAmount: 100 // emoji
        });

        suckerDeployerConfig[0] = JBSuckerDeployerConfig({deployer: ARB_SUCKER_DEPLOYER, mappings: tokenMapping});

        REVSuckerDeploymentConfig memory revConfig =
            REVSuckerDeploymentConfig({deployerConfigurations: suckerDeployerConfig, salt: "SALTY"});

        // Arbitrum chainid so the deployer works
        vm.chainId(42_161);
        vm.prank(multisig());

        // Ensure Registry is called
        vm.expectEmit();
        address[] memory suckers = new address[](1);
        suckers[0] = 0xfF4c4c3Aa7bD09d9bbF713CE6dE7492F304540E3;
        emit IJBSuckerRegistry.SuckersDeployedFor(REVNET_ID, suckers, suckerDeployerConfig, address(BASIC_DEPLOYER));

        BASIC_DEPLOYER.deploySuckersFor(REVNET_ID, ENCODED_CONFIG, revConfig);

        // Ensure it's registered
        bool isSucker = SUCKER_REGISTRY.isSuckerOf(REVNET_ID, suckers[0]);
        assertEq(isSucker, true);
    }
}