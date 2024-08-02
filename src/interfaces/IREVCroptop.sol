// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CTPublisher} from "@croptop/core/src/CTPublisher.sol";

import {IREVTiered721Hook} from "./IREVTiered721Hook.sol";

interface IREVCroptop is IREVTiered721Hook {
    function PUBLISHER() external view returns (CTPublisher);
}
