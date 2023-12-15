pragma solidity ^0.8.0;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {JBTerminalConfig} from "@juice/structs/JBTerminalConfig.sol";
import {REVBuybackHookSetupData} from "../structs/REVBuybackHookSetupData.sol";
import {REVDeployParams} from "../structs/REVDeployParams.sol";

interface IREVBasicDeployer {
    function deployRevnetFor(
        address boostOperator,
        string memory revnetMetadata,
        string memory name,
        string memory symbol,
        REVDeployParams memory deployData,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookSetupData memory buybackHookSetupData
    )
        external
        returns (uint256 revnetId);
}
