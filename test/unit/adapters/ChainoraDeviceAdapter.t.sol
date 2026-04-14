// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraDeviceAdapterTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testSubmitVerificationMarksUserVerifiedAndAdvancesNonce() external {
        uint256 nonceBefore = deviceAdapter.nextNonce(member1);

        _verifyUser(member1);

        assertTrue(deviceAdapter.isDeviceVerified(member1));
        assertEq(deviceAdapter.nextNonce(member1), nonceBefore + 1);
    }

    function testSubmitVerificationRejectsUntrustedVerifier() external {
        (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature) =
            _signedDeviceVerification(member1, 0xB0B);

        vm.prank(member1);
        vm.expectRevert(Errors.UntrustedVerifier.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testSubmitVerificationRejectsInvalidSignature() external {
        IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation =
            _deviceVerificationAttestation(member1);

        bytes memory signature = hex"1234";

        vm.prank(member1);
        vm.expectRevert(Errors.InvalidAttestationSignature.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testSubmitVerificationRejectsExpiredAttestation() external {
        IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation =
            _deviceVerificationAttestation(member1, deviceAdapter.nextNonce(member1), uint64(block.timestamp));
        bytes memory signature = _signDeviceVerification(attestation, DEVICE_VERIFIER_KEY);

        vm.warp(block.timestamp + 1);
        vm.prank(member1);
        vm.expectRevert(Errors.AttestationExpired.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testSubmitVerificationRejectsUserMismatch() external {
        (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature) =
            _signedDeviceVerification(member1, DEVICE_VERIFIER_KEY);

        vm.prank(outsider);
        vm.expectRevert(Errors.AttestationUserMismatch.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testSubmitVerificationRejectsIncorrectNonce() external {
        IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation = _deviceVerificationAttestation(
            member1, deviceAdapter.nextNonce(member1) + 1, uint64(block.timestamp + 1 days)
        );
        bytes memory signature = _signDeviceVerification(attestation, DEVICE_VERIFIER_KEY);

        vm.prank(member1);
        vm.expectRevert(Errors.InvalidAttestationNonce.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testSubmitVerificationRejectsAlreadyVerifiedUser() external {
        _verifyUser(member1);

        (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature) =
            _signedDeviceVerification(member1, DEVICE_VERIFIER_KEY);

        vm.prank(member1);
        vm.expectRevert(Errors.AlreadyVerified.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testSetTrustVerifierRequiresTimelock() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        deviceAdapter.setTrustVerifier(outsider, true);
    }

    function testTimelockCanAddAndRemoveVerifier() external {
        address newVerifier = vm.addr(0xC0FFEE);

        vm.prank(address(timelock));
        deviceAdapter.setTrustVerifier(newVerifier, true);
        assertTrue(deviceAdapter.trustVerifier(newVerifier));

        vm.prank(address(timelock));
        deviceAdapter.setTrustVerifier(newVerifier, false);
        assertFalse(deviceAdapter.trustVerifier(newVerifier));
    }

    function testRevokeUserRequiresTimelock() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        deviceAdapter.revokeUser(member1);
    }

    function testRevokeUserClearsVerificationAndInvalidatesPendingNonce() external {
        _verifyUser(member1);

        IChainoraDeviceAdapter.DeviceVerificationAttestation memory staleAttestation =
            _deviceVerificationAttestation(member1);
        bytes memory signature = _signDeviceVerification(staleAttestation, DEVICE_VERIFIER_KEY);

        vm.prank(address(timelock));
        deviceAdapter.revokeUser(member1);

        assertFalse(deviceAdapter.isDeviceVerified(member1));
        assertEq(deviceAdapter.nextNonce(member1), staleAttestation.nonce + 1);

        vm.prank(member1);
        vm.expectRevert(Errors.InvalidAttestationNonce.selector);
        deviceAdapter.submitVerification(staleAttestation, signature);
    }

    function testRemovedVerifierCannotVerifyNewUsers() external {
        vm.prank(address(timelock));
        deviceAdapter.setTrustVerifier(deviceVerifier, false);

        (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature) =
            _signedDeviceVerification(member1, DEVICE_VERIFIER_KEY);

        vm.prank(member1);
        vm.expectRevert(Errors.UntrustedVerifier.selector);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function testRevokedUserCanVerifyAgainWithFreshNonce() external {
        _verifyUser(member1);

        vm.prank(address(timelock));
        deviceAdapter.revokeUser(member1);

        (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature) =
            _signedDeviceVerification(member1, DEVICE_VERIFIER_KEY);

        vm.prank(member1);
        deviceAdapter.submitVerification(attestation, signature);

        assertTrue(deviceAdapter.isDeviceVerified(member1));
    }
}
