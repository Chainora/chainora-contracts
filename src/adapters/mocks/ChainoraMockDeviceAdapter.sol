// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";
import {Errors} from "src/libraries/Errors.sol";

contract ChainoraMockDeviceAdapter is IChainoraDeviceAdapter {
    mapping(address => bool) private _verified;
    mapping(address => uint256) public nextNonce;

    function setVerified(address user, bool value) external {
        _verified[user] = value;
    }

    function submitVerification(DeviceVerificationAttestation calldata attestation, bytes calldata) external {
        if (attestation.user == address(0)) revert Errors.ZeroAddress();
        if (attestation.user != msg.sender) revert Errors.AttestationUserMismatch();
        if (_verified[attestation.user]) revert Errors.AlreadyVerified();
        if (block.timestamp > attestation.deadline) revert Errors.AttestationExpired();
        if (attestation.nonce != nextNonce[attestation.user]) revert Errors.InvalidAttestationNonce();

        _verified[attestation.user] = true;
        nextNonce[attestation.user] = attestation.nonce + 1;
    }

    function isDeviceVerified(address user) external view returns (bool) {
        return _verified[user];
    }
}
