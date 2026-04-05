// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";

interface IChainoraRoscaPool {
    function initialize(Types.PoolInitConfig calldata initConfig) external;
}
