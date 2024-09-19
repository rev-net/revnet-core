// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import /* {*} from */ "@bananapus/core/test/helpers/TestBaseWorkflow.sol";
import /* {*} from "@bananapus/721-hook/src/JB721TiersHookDeployer.sol";
    import /* {*} from */ "./../src/REVDeployer.sol";
import /* {*} from */ "./../src/REVLoans.sol";
import "@croptop/core/src/CTPublisher.sol";

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "@croptop/core/script/helpers/CroptopDeploymentLib.sol";
import "@bananapus/swap-terminal/script/helpers/SwapTerminalDeploymentLib.sol";
import "@bananapus/buyback-hook/script/helpers/BuybackDeploymentLib.sol";

import {JBRedemptions} from "@bananapus/core/src/libraries/JBRedemptions.sol";
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
import {JB721TiersHookDeployer} from "@bananapus/721-hook/src/JB721TiersHookDeployer.sol";
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

contract REVLoansCallHandler is JBTest {
    uint256 public COLLATERAL_SUM;
    uint256 public COLLATERAL_RETURNED;
    uint256 public BORROWED_SUM;
    uint256 public RUNS;
    uint256 REVNET_ID;
    address USER;

    IJBMultiTerminal TERMINAL;
    IREVLoans LOANS;
    IJBPermissions PERMS;
    IJBTokens TOKENS;

    constructor(
        IJBMultiTerminal terminal,
        IREVLoans loans,
        IJBPermissions permissions,
        IJBTokens tokens,
        uint256 revnetId,
        address beneficiary
    ) {
        TERMINAL = terminal;
        LOANS = loans;
        PERMS = permissions;
        TOKENS = tokens;
        REVNET_ID = revnetId;
        USER = beneficiary;
    }

    modifier useActor() {
        vm.startPrank(USER);
        _;
        vm.stopPrank();
    }

    function payBorrow(uint256 amount) public virtual useActor {
        uint256 payAmount = bound(amount, 1 ether, 10 ether);
        uint256 prepaidFee = bound(amount, 10, 200);

        vm.deal(USER, payAmount);

        uint256 receivedTokens = TERMINAL.pay{value: payAmount}(REVNET_ID, JBConstants.NATIVE_TOKEN, 0, USER, 0, "", "");
        uint256 borrowable =
            LOANS.borrowableAmountFrom(REVNET_ID, receivedTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        // User must give the loans contract permission, similar to an "approve" call, we're just spoofing to save time.
        mockExpect(
            address(PERMS),
            abi.encodeCall(IJBPermissions.hasPermission, (address(LOANS), USER, 2, 10, true, true)),
            abi.encode(true)
        );

        REVLoanSource memory sauce = REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: TERMINAL});
        (, REVLoan memory lastLoan) =
            LOANS.borrowFrom(REVNET_ID, sauce, borrowable, receivedTokens, payable(USER), prepaidFee);

        COLLATERAL_SUM += receivedTokens;
        BORROWED_SUM += lastLoan.amount;
        ++RUNS;
    }

    function repayLoan(uint256 percentToPayDown, uint256 daysToWarp) public virtual useActor {
        // Skip this if there are no loans to pay down
        if (RUNS == 0) {
            return;
        }

        uint256 denominator = 10_000;
        percentToPayDown = bound(percentToPayDown, 1000, denominator);
        daysToWarp = bound(daysToWarp, 10, 100);
        daysToWarp = daysToWarp * 1 days;

        vm.warp(block.timestamp + daysToWarp);

        // get the loan ID
        uint256 id = (REVNET_ID * 1_000_000_000_000) + RUNS;
        REVLoan memory latestLoan = LOANS.loanOf(id);

        // skip if we don't find the loan
        if (latestLoan.amount == 0) return;

        // calc percentage to pay down
        uint256 amountPaidDown;

        uint256 collateralReturned = mulDiv(latestLoan.collateral, percentToPayDown, 10_000);

        uint256 newCollateral = latestLoan.collateral - collateralReturned;
        uint256 borrowableFromNewCollateral =
            LOANS.borrowableAmountFrom(REVNET_ID, newCollateral, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        // Needed for edge case seeds like 17721, 11407, 334
        if (borrowableFromNewCollateral > 0) borrowableFromNewCollateral -= 1;

        uint256 amountDiff =
            borrowableFromNewCollateral > latestLoan.amount ? 0 : latestLoan.amount - borrowableFromNewCollateral;

        amountPaidDown = amountDiff;

        // Calculate the fee.
        {
            // Keep a reference to the time since the loan was created.
            uint256 timeSinceLoanCreated = block.timestamp - latestLoan.createdAt;

            // If the loan period has passed the prepaid time frame, take a fee.
            if (timeSinceLoanCreated > latestLoan.prepaidDuration) {
                // Calculate the prepaid fee for the amount being paid back.
                uint256 prepaidAmount =
                    JBFees.feeAmountFrom({amount: amountDiff, feePercent: latestLoan.prepaidFeePercent});

                // Calculate the fee as a linear proportion given the amount of time that has passed.
                // sourceFeeAmount = mulDiv(amount, timeSinceLoanCreated, LOAN_LIQUIDATION_DURATION) - prepaidAmount;
                amountPaidDown += JBFees.feeAmountFrom({
                    amount: amountDiff - prepaidAmount,
                    feePercent: mulDiv(timeSinceLoanCreated, JBConstants.MAX_FEE, 3650 days)
                });
            }
        }

        // empty allowance data
        JBSingleAllowance memory allowance;

        vm.deal(USER, type(uint256).max);
        LOANS.repayLoan{value: amountPaidDown}(id, amountPaidDown, collateralReturned, payable(USER), allowance);

        COLLATERAL_RETURNED += collateralReturned;
        COLLATERAL_SUM -= collateralReturned;
        if (BORROWED_SUM >= amountDiff) BORROWED_SUM -= amountDiff;
    }

    function reallocateCollateralFromLoan(uint16 collateralPercent, uint256 amountToPay) public virtual useActor {
        // used for percentage calculations
        uint256 denominator = 10_000;

        // Skip this if there are no loans to refinance
        if (RUNS == 0) {
            return;
        }

        // 0.0001-100%
        uint256 collateralPercentToTransfer = bound(uint256(collateralPercent), 1, denominator);
        amountToPay = bound(amountToPay, 1e15, 1000e18);

        // get the loan ID
        uint256 id = (REVNET_ID * 1_000_000_000_000) + RUNS;
        REVLoan memory latestLoan = LOANS.loanOf(id);

        // skip if we don't find a loan
        if (latestLoan.amount == 0) return;

        // try paying instead
        vm.deal(USER, amountToPay);
        uint256 collateralToAdd =
            TERMINAL.pay{value: amountToPay}(REVNET_ID, JBConstants.NATIVE_TOKEN, 0, USER, 0, "", "");

        // 0.0001-100% in token terms
        uint256 collateralToTransfer = mulDiv(latestLoan.collateral, collateralPercentToTransfer, denominator);

        // get the new amount to borrow
        uint256 newAmountInFull = LOANS.borrowableAmountFrom(
            REVNET_ID, collateralToTransfer + collateralToAdd, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );

        (,,, REVLoan memory newLoan) = LOANS.reallocateCollateralFromLoan(
            id,
            collateralToTransfer,
            REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: TERMINAL}),
            newAmountInFull,
            collateralToAdd,
            payable(USER),
            0
        );

        COLLATERAL_SUM += collateralToAdd;
        BORROWED_SUM += (newLoan.amount - latestLoan.amount);
    }
}

contract InvariantREVLoansTests is StdInvariant, TestBaseWorkflow, JBTest {
    // A library that parses the packed ruleset metadata into a friendlier format.
    using JBRulesetMetadataResolver for JBRuleset;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 REV_DEPLOYER_SALT = "REVDeployer";
    bytes32 ERC20_SALT = "REV_TOKEN";

    // Handlers
    REVLoansCallHandler PAY_HANDLER;

    REVDeployer REV_DEPLOYER;
    JB721TiersHook EXAMPLE_HOOK;

    /// @notice Deploys tiered ERC-721 hooks for revnets.
    IJB721TiersHookDeployer HOOK_DEPLOYER;
    IJB721TiersHookStore HOOK_STORE;
    IJBAddressRegistry ADDRESS_REGISTRY;

    IREVLoans LOANS_CONTRACT;

    /// @notice Deploys and tracks suckers for revnets.
    IJBSuckerRegistry SUCKER_REGISTRY;

    CTPublisher PUBLISHER;

    // When the second project is deployed, track the block.timestamp.
    uint256 INITIAL_TIMESTAMP;

    uint256 FEE_PROJECT_ID;
    uint256 REVNET_ID;

    address USER = makeAddr("user");

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
        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: accountingContextsToAccept});

        // The project's revnet stage configurations.
        REVStageConfig[] memory stageConfigurations = new REVStageConfig[](3);

        {
            REVAutoMint[] memory mintConfs = new REVAutoMint[](1);
            mintConfs[0] = REVAutoMint({
                chainId: uint32(block.chainid),
                count: uint104(70_000 * decimalMultiplier),
                beneficiary: multisig()
            });

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
            autoMints: new REVAutoMint[](0),
            splitPercent: 2000, // 20%
            initialIssuance: 0, // inherit from previous cycle.
            issuanceDecayFrequency: 180 days,
            issuanceDecayPercent: JBConstants.MAX_DECAY_PERCENT / 2,
            cashOutTaxRate: 1000, //0.1
            extraMetadata: 0
        });

        stageConfigurations[2] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[1].startsAtOrAfter + (20 * 365 days)),
            autoMints: new REVAutoMint[](0),
            splitPercent: 0,
            initialIssuance: 1, // this is a special number that is as close to max price as we can get.
            issuanceDecayFrequency: 0,
            issuanceDecayPercent: 0,
            cashOutTaxRate: 500, // 0.05
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
            allowCrosschainSuckerExtension: true
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

    function getSecondProjectConfig() internal view returns (FeeProjectConfig memory) {
        // Define constants
        string memory name = "NANA";
        string memory symbol = "$NANA";
        string memory projectUri = "ipfs://QmNRHT91HcDgMcenebYX7rJigt77cgNxosvuhX21wkF3tx";
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
        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: accountingContextsToAccept});

        // The project's revnet stage configurations.
        REVStageConfig[] memory stageConfigurations = new REVStageConfig[](3);

        {
            REVAutoMint[] memory mintConfs = new REVAutoMint[](1);
            mintConfs[0] = REVAutoMint({
                chainId: uint32(block.chainid),
                count: uint104(70_000 * decimalMultiplier),
                beneficiary: multisig()
            });

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
            startsAtOrAfter: uint40(stageConfigurations[0].startsAtOrAfter + 365 days),
            autoMints: new REVAutoMint[](0),
            splitPercent: 9000, // 90%
            initialIssuance: 0, // this is a special number that is as close to max price as we can get.
            issuanceDecayFrequency: 180 days,
            issuanceDecayPercent: JBConstants.MAX_DECAY_PERCENT / 2,
            cashOutTaxRate: 0, // 0.0%
            extraMetadata: 0
        });

        stageConfigurations[2] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[1].startsAtOrAfter + (20 * 365 days)),
            autoMints: new REVAutoMint[](0),
            splitPercent: 0,
            initialIssuance: 0, // this is a special number that is as close to max price as we can get.
            issuanceDecayFrequency: 0,
            issuanceDecayPercent: 0,
            cashOutTaxRate: 0, // 0.0%
            extraMetadata: 0
        });

        REVLoanSource[] memory _loanSources = new REVLoanSource[](1);
        _loanSources[0] = REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: jbMultiTerminal()});

        // The project's revnet configuration
        REVConfig memory revnetConfiguration = REVConfig({
            description: REVDescription(name, symbol, projectUri, "NANA_TOKEN"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stageConfigurations,
            loanSources: _loanSources,
            loans: address(LOANS_CONTRACT),
            allowCrosschainSuckerExtension: true
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
            REVBuybackHookConfig({hook: IJBBuybackHook(address(0)), poolConfigurations: buybackPoolConfigurations});

        return FeeProjectConfig({
            configuration: revnetConfiguration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: REVSuckerDeploymentConfig({
                deployerConfigurations: new JBSuckerDeployerConfig[](0),
                salt: keccak256(abi.encodePacked("NANA"))
            })
        });
    }

    function setUp() public override {
        super.setUp();

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig());

        HOOK_STORE = new JB721TiersHookStore();

        EXAMPLE_HOOK = new JB721TiersHook(jbDirectory(), jbPermissions(), jbRulesets(), HOOK_STORE, multisig());

        ADDRESS_REGISTRY = new JBAddressRegistry();

        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());

        PUBLISHER = new CTPublisher(jbController(), jbPermissions(), FEE_PROJECT_ID, multisig());

        REV_DEPLOYER = new REVDeployer{salt: REV_DEPLOYER_SALT}(
            jbController(), SUCKER_REGISTRY, FEE_PROJECT_ID, HOOK_DEPLOYER, PUBLISHER
        );

        LOANS_CONTRACT = new REVLoans(jbProjects(), FEE_PROJECT_ID, permit2(), address(this));

        // Approve the basic deployer to configure the project.
        vm.prank(address(multisig()));
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Build the config.
        FeeProjectConfig memory feeProjectConfig = getFeeProjectConfig();

        // Configure the project.
        REVNET_ID = REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, // Zero to deploy a new revnet
            configuration: feeProjectConfig.configuration,
            terminalConfigurations: feeProjectConfig.terminalConfigurations,
            buybackHookConfiguration: feeProjectConfig.buybackHookConfiguration,
            suckerDeploymentConfiguration: feeProjectConfig.suckerDeploymentConfiguration
        });

        // Configure second revnet
        FeeProjectConfig memory fee2Config = getSecondProjectConfig();

        // Configure the second project.
        REVNET_ID = REV_DEPLOYER.deployFor({
            revnetId: 0, // Zero to deploy a new revnet
            configuration: fee2Config.configuration,
            terminalConfigurations: fee2Config.terminalConfigurations,
            buybackHookConfiguration: fee2Config.buybackHookConfiguration,
            suckerDeploymentConfiguration: fee2Config.suckerDeploymentConfiguration
        });

        INITIAL_TIMESTAMP = block.timestamp;

        // Deploy handlers and assign them as targets
        PAY_HANDLER =
            new REVLoansCallHandler(jbMultiTerminal(), LOANS_CONTRACT, jbPermissions(), jbTokens(), REVNET_ID, USER);

        // Calls to perform via the handler
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = REVLoansCallHandler.payBorrow.selector;
        selectors[1] = REVLoansCallHandler.repayLoan.selector;
        selectors[2] = REVLoansCallHandler.reallocateCollateralFromLoan.selector;

        targetContract(address(PAY_HANDLER));
        targetSelector(FuzzSelector({addr: address(PAY_HANDLER), selectors: selectors}));

        vm.deal(USER, type(uint256).max);
    }

    function invariant_A_Solvency() public {
        IJBTerminal[] memory terminals = new IJBTerminal[](1);
        terminals[0] = jbMultiTerminal();

        // Get the total amount of tokens in circulation.
        uint256 totalSupply = jbTokens().totalSupplyOf(REVNET_ID);

        // Keep a reference to the current stage.
        JBRuleset memory currentStage = jbController().RULESETS().currentOf(REVNET_ID);

        // Get the surplus of all the revnet's terminals in terms of the native currency.
        uint256 totalSurplus = JBSurplus.currentSurplusOf({
            projectId: REVNET_ID,
            terminals: terminals,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        // Sans the borrowed amount, otherwise we would use borrowableAmountFrom()
        uint256 totalCollateralValue = JBRedemptions.reclaimFrom(
            totalSurplus, LOANS_CONTRACT.totalCollateralOf(REVNET_ID), totalSupply, currentStage.redemptionRate()
        );
        uint256 totalBorrowed = LOANS_CONTRACT.totalBorrowedFrom(REVNET_ID, jbMultiTerminal(), JBConstants.NATIVE_TOKEN);
        assertGe(totalCollateralValue, totalBorrowed);
    }

    function invariant_B_User_Balance_And_Collateral() public {
        IJBToken token = jbTokens().tokenOf(REVNET_ID);

        uint256 userTokenBalance = token.balanceOf(USER);
        if (PAY_HANDLER.RUNS() > 0) assertGe(userTokenBalance, PAY_HANDLER.COLLATERAL_RETURNED());

        // Ensure REVLoans and our handler/user have the same provided collateral amounts.
        assertEq(PAY_HANDLER.COLLATERAL_SUM(), LOANS_CONTRACT.totalCollateralOf(REVNET_ID));
    }
}
