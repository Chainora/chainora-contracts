// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

contract ChainoraReputationAdapter is Events, EIP712, IChainoraReputationAdapter {
    using ECDSA for bytes32;

    bytes32 private constant _REPUTATION_SCORE_UPDATE_TYPEHASH =
        keccak256("ReputationScoreUpdate(address user,uint256 score,uint256 nonce)");
    bytes32 private constant _REPUTATION_SCORE_BATCH_ATTESTATION_TYPEHASH =
        keccak256("ReputationScoreBatchAttestation(bytes32 updatesHash,uint64 deadline)");

    string public constant EIP712_NAME = "ChainoraReputationAdapter";
    string public constant EIP712_VERSION = "1";

    address public timelock;

    mapping(address => uint256) public nextNonce;
    mapping(address => bool) public trustVerifier;

    mapping(address => uint256) private _liveScore;
    mapping(bytes32 => mapping(address => uint256)) private _snapshotScore;
    uint256 private _snapshotNonce;

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Errors.Unauthorized();
        _;
    }

    constructor(address timelock_) EIP712(EIP712_NAME, EIP712_VERSION) {
        if (timelock_ == address(0)) revert Errors.ZeroAddress();
        timelock = timelock_;
    }

    function setTrustVerifier(address verifier, bool allowed) external onlyTimelock {
        if (verifier == address(0)) revert Errors.ZeroAddress();

        trustVerifier[verifier] = allowed;
        emit ChainoraReputationTrustVerifierSet(verifier, allowed);
    }

    function submitScores(ReputationScoreUpdate[] calldata updates, uint64 deadline, bytes calldata signature)
        external
    {
        if (updates.length == 0) revert Errors.InvalidConfig();
        if (block.timestamp > deadline) revert Errors.AttestationExpired();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_REPUTATION_SCORE_BATCH_ATTESTATION_TYPEHASH, _hashUpdates(updates), deadline))
        );
        address signer = _recoverSigner(digest, signature);
        if (!trustVerifier[signer]) revert Errors.UntrustedVerifier();

        uint256 len = updates.length;
        for (uint256 i = 0; i < len; i++) {
            ReputationScoreUpdate calldata update = updates[i];
            address user = update.user;
            if (user == address(0)) revert Errors.ZeroAddress();

            for (uint256 j = i + 1; j < len; j++) {
                if (updates[j].user == user) revert Errors.DuplicateAttestationUser();
            }

            uint256 expectedNonce = nextNonce[user];
            if (update.nonce != expectedNonce) revert Errors.InvalidAttestationNonce();

            _liveScore[user] = update.score;
            nextNonce[user] = expectedNonce + 1;

            emit ChainoraReputationScoreUpdated(user, signer, update.score, update.nonce);
        }
    }

    function scoreOf(address user) external view returns (uint256) {
        return _liveScore[user];
    }

    function snapshotPeriodScores(uint256, uint256, uint256, address[] calldata members)
        external
        returns (bytes32 snapshotId)
    {
        snapshotId = keccak256(abi.encodePacked(address(this), block.chainid, _snapshotNonce++));
        uint256 len = members.length;
        for (uint256 i = 0; i < len; i++) {
            _snapshotScore[snapshotId][members[i]] = _liveScore[members[i]];
        }
    }

    function scoreOfAt(bytes32 snapshotId, address user) external view returns (uint256) {
        return _snapshotScore[snapshotId][user];
    }

    function _hashUpdates(ReputationScoreUpdate[] calldata updates) private pure returns (bytes32) {
        uint256 len = updates.length;
        bytes32[] memory structHashes = new bytes32[](len);

        for (uint256 i = 0; i < len; i++) {
            ReputationScoreUpdate calldata update = updates[i];
            structHashes[i] =
                keccak256(abi.encode(_REPUTATION_SCORE_UPDATE_TYPEHASH, update.user, update.score, update.nonce));
        }

        bytes32 hash;
        assembly ("memory-safe") {
            hash := keccak256(add(structHashes, 32), mul(mload(structHashes), 32))
        }
        return hash;
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) private pure returns (address signer) {
        (address recovered, ECDSA.RecoverError err, bytes32 errArg) = ECDSA.tryRecover(digest, signature);
        errArg;
        if (err != ECDSA.RecoverError.NoError || recovered == address(0)) {
            revert Errors.InvalidAttestationSignature();
        }

        return recovered;
    }
}
