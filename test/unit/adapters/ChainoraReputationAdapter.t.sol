// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ChainoraReputationAdapter} from "src/adapters/ChainoraReputationAdapter.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

contract ChainoraReputationAdapterTest is Test {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant REPUTATION_SCORE_UPDATE_TYPEHASH =
        keccak256("ReputationScoreUpdate(address user,uint256 score,uint256 nonce)");
    bytes32 internal constant REPUTATION_SCORE_BATCH_ATTESTATION_TYPEHASH =
        keccak256("ReputationScoreBatchAttestation(bytes32 updatesHash,uint64 deadline)");
    uint256 internal constant REPUTATION_VERIFIER_KEY = 0xBEEFCAFE;

    ChainoraReputationAdapter internal reputationAdapter;
    address internal trustedVerifier;
    address internal user1 = address(0xA11CE);
    address internal user2 = address(0xB0B);

    function setUp() external {
        reputationAdapter = new ChainoraReputationAdapter(address(this));
        trustedVerifier = vm.addr(REPUTATION_VERIFIER_KEY);
        reputationAdapter.setTrustVerifier(trustedVerifier, true);
    }

    function testSubmitScoresUpdatesMultipleUsersAndAdvancesNonces() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](2);
        updates[0] = _scoreUpdate(user1, 100);
        updates[1] = _scoreUpdate(user2, 200);

        bytes memory signature = _signScoreBatch(updates, uint64(block.timestamp + 1 days), REPUTATION_VERIFIER_KEY);
        reputationAdapter.submitScores(updates, uint64(block.timestamp + 1 days), signature);

        assertEq(reputationAdapter.scoreOf(user1), 100);
        assertEq(reputationAdapter.scoreOf(user2), 200);
        assertEq(reputationAdapter.nextNonce(user1), 1);
        assertEq(reputationAdapter.nextNonce(user2), 1);
    }

    function testSubmitScoresRejectsUntrustedVerifier() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](1);
        updates[0] = _scoreUpdate(user1, 100);

        bytes memory signature = _signScoreBatch(updates, uint64(block.timestamp + 1 days), 0xCAFE);

        vm.expectRevert(Errors.UntrustedVerifier.selector);
        reputationAdapter.submitScores(updates, uint64(block.timestamp + 1 days), signature);
    }

    function testSubmitScoresRejectsInvalidSignature() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](1);
        updates[0] = _scoreUpdate(user1, 100);

        vm.expectRevert(Errors.InvalidAttestationSignature.selector);
        reputationAdapter.submitScores(updates, uint64(block.timestamp + 1 days), hex"1234");
    }

    function testSubmitScoresRejectsExpiredAttestation() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](1);
        updates[0] = _scoreUpdate(user1, 100);

        uint64 deadline = uint64(block.timestamp);
        bytes memory signature = _signScoreBatch(updates, deadline, REPUTATION_VERIFIER_KEY);

        vm.warp(block.timestamp + 1);
        vm.expectRevert(Errors.AttestationExpired.selector);
        reputationAdapter.submitScores(updates, deadline, signature);
    }

    function testSubmitScoresRejectsInvalidNonce() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](1);
        updates[0] = IChainoraReputationAdapter.ReputationScoreUpdate({user: user1, score: 100, nonce: 1});

        bytes memory signature = _signScoreBatch(updates, uint64(block.timestamp + 1 days), REPUTATION_VERIFIER_KEY);

        vm.expectRevert(Errors.InvalidAttestationNonce.selector);
        reputationAdapter.submitScores(updates, uint64(block.timestamp + 1 days), signature);
    }

    function testSubmitScoresRejectsDuplicateUsersInBatch() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](2);
        updates[0] = _scoreUpdate(user1, 100);
        updates[1] = _scoreUpdate(user1, 200);

        bytes memory signature = _signScoreBatch(updates, uint64(block.timestamp + 1 days), REPUTATION_VERIFIER_KEY);

        vm.expectRevert(Errors.DuplicateAttestationUser.selector);
        reputationAdapter.submitScores(updates, uint64(block.timestamp + 1 days), signature);
    }

    function testSnapshotPeriodScoresCopiesLiveScores() external {
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](2);
        updates[0] = _scoreUpdate(user1, 100);
        updates[1] = _scoreUpdate(user2, 200);

        reputationAdapter.submitScores(
            updates,
            uint64(block.timestamp + 1 days),
            _signScoreBatch(updates, uint64(block.timestamp + 1 days), REPUTATION_VERIFIER_KEY)
        );

        address[] memory members = new address[](2);
        members[0] = user1;
        members[1] = user2;

        bytes32 snapshotId = reputationAdapter.snapshotPeriodScores(1, 1, 1, members);

        IChainoraReputationAdapter.ReputationScoreUpdate[] memory nextUpdates =
            new IChainoraReputationAdapter.ReputationScoreUpdate[](1);
        nextUpdates[0] = IChainoraReputationAdapter.ReputationScoreUpdate({
            user: user1, score: 999, nonce: reputationAdapter.nextNonce(user1)
        });
        reputationAdapter.submitScores(
            nextUpdates,
            uint64(block.timestamp + 1 days),
            _signScoreBatch(nextUpdates, uint64(block.timestamp + 1 days), REPUTATION_VERIFIER_KEY)
        );

        assertEq(reputationAdapter.scoreOfAt(snapshotId, user1), 100);
        assertEq(reputationAdapter.scoreOfAt(snapshotId, user2), 200);
    }

    function _scoreUpdate(address user, uint256 score)
        internal
        view
        returns (IChainoraReputationAdapter.ReputationScoreUpdate memory)
    {
        return IChainoraReputationAdapter.ReputationScoreUpdate({
            user: user, score: score, nonce: reputationAdapter.nextNonce(user)
        });
    }

    function _signScoreBatch(
        IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates,
        uint64 deadline,
        uint256 signerKey
    ) internal view returns (bytes memory signature) {
        bytes32 digest = _scoreBatchDigest(updates, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _scoreBatchDigest(IChainoraReputationAdapter.ReputationScoreUpdate[] memory updates, uint64 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32[] memory structHashes = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            IChainoraReputationAdapter.ReputationScoreUpdate memory update = updates[i];
            structHashes[i] =
                keccak256(abi.encode(REPUTATION_SCORE_UPDATE_TYPEHASH, update.user, update.score, update.nonce));
        }

        bytes32 updatesHash;
        assembly ("memory-safe") {
            updatesHash := keccak256(add(structHashes, 32), mul(mload(structHashes), 32))
        }

        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ChainoraReputationAdapter")),
                keccak256(bytes("1")),
                block.chainid,
                address(reputationAdapter)
            )
        );
        bytes32 structHash = keccak256(abi.encode(REPUTATION_SCORE_BATCH_ATTESTATION_TYPEHASH, updatesHash, deadline));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
