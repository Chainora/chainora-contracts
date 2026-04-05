// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";

contract ChainoraMockDeviceAdapter is IChainoraDeviceAdapter {
    mapping(address => bool) private _verified;

    function setVerified(address user, bool value) external {
        _verified[user] = value;
    }

    function isDeviceVerified(address user) external view returns (bool) {
        return _verified[user];
    }
}
