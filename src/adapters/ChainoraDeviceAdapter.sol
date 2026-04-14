// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";

contract ChainoraDeviceAdapter is Events, IChainoraDeviceAdapter {
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _DEVICE_VERIFICATION_ATTESTATION_TYPEHASH =
        keccak256("DeviceVerificationAttestation(address user,uint256 nonce,uint64 deadline)");
    bytes32 private constant _EIP712_NAME_HASH = keccak256(bytes(EIP712_NAME));
    bytes32 private constant _EIP712_VERSION_HASH = keccak256(bytes(EIP712_VERSION));
    uint256 private constant _SECP256K1N_DIV_2 = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    string public constant EIP712_NAME = "ChainoraDeviceAdapter";
    string public constant EIP712_VERSION = "1";

    address public timelock;

    mapping(address => bool) private _verified;
    mapping(address => uint256) public nextNonce;
    mapping(address => bool) public trustVerifier;

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Errors.Unauthorized();
        _;
    }

    constructor(address timelock_) {
        if (timelock_ == address(0)) revert Errors.ZeroAddress();
        timelock = timelock_;
    }

    function setTrustVerifier(address verifier, bool allowed) external onlyTimelock {
        if (verifier == address(0)) revert Errors.ZeroAddress();

        trustVerifier[verifier] = allowed;
        emit ChainoraDeviceTrustVerifierSet(verifier, allowed);
    }

    function revokeUser(address user) external onlyTimelock {
        if (user == address(0)) revert Errors.ZeroAddress();

        _verified[user] = false;
        uint256 next = nextNonce[user] + 1;
        nextNonce[user] = next;

        emit ChainoraDeviceVerificationRevoked(user, next);
    }

    function submitVerification(DeviceVerificationAttestation calldata attestation, bytes calldata signature) external {
        address user = attestation.user;
        if (user == address(0)) revert Errors.ZeroAddress();
        if (user != msg.sender) revert Errors.AttestationUserMismatch();
        if (_verified[user]) revert Errors.AlreadyVerified();
        if (block.timestamp > attestation.deadline) revert Errors.AttestationExpired();

        uint256 expectedNonce = nextNonce[user];
        if (attestation.nonce != expectedNonce) revert Errors.InvalidAttestationNonce();

        address signer = _recoverSigner(_hashTypedData(attestation), signature);
        if (!trustVerifier[signer]) revert Errors.UntrustedVerifier();

        _verified[user] = true;
        nextNonce[user] = expectedNonce + 1;

        emit ChainoraDeviceVerified(user, signer, attestation.nonce);
    }

    function isDeviceVerified(address user) external view returns (bool) {
        return _verified[user];
    }

    function _hashTypedData(DeviceVerificationAttestation calldata attestation) private view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                _DEVICE_VERIFICATION_ATTESTATION_TYPEHASH, attestation.user, attestation.nonce, attestation.deadline
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(_EIP712_DOMAIN_TYPEHASH, _EIP712_NAME_HASH, _EIP712_VERSION_HASH, block.chainid, address(this))
        );
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) private pure returns (address signer) {
        if (signature.length != 65) revert Errors.InvalidAttestationSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert Errors.InvalidAttestationSignature();
        if (uint256(s) > _SECP256K1N_DIV_2) revert Errors.InvalidAttestationSignature();

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert Errors.InvalidAttestationSignature();
    }
}
