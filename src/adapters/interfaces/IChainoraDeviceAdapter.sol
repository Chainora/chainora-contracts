// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainoraDeviceAdapter {
    struct DeviceVerificationAttestation {
        address user;
        uint256 nonce;
        uint64 deadline;
    }

    function submitVerification(DeviceVerificationAttestation calldata attestation, bytes calldata signature) external;

    function isDeviceVerified(address user) external view returns (bool);

    function nextNonce(address user) external view returns (uint256);
}
