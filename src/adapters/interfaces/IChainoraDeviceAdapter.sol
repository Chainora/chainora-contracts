// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainoraDeviceAdapter {
    function isDeviceVerified(address user) external view returns (bool);
}
