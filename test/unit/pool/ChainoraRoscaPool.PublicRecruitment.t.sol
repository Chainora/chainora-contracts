// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolPublicRecruitmentTest is ChainoraTestBase {
    ChainoraRoscaPool internal publicPool;

    function setUp() external {
        _setUpProtocolAndPool();

        _verifyUser(member1);
        (publicPool,) = _createPoolFor(member1, true, 3);
        _approvePoolFor(address(publicPool), member2);
        _approvePoolFor(address(publicPool), outsider);
    }

    function testSubmitJoinRequestRevertsForPrivatePool() external {
        _verifyUser(member2);
        (ChainoraRoscaPool privatePool,) = _createPoolFor(member2, false, 3);

        vm.prank(outsider);
        vm.expectRevert(Errors.InvalidState.selector);
        privatePool.submitJoinRequest();
    }

    function testSubmitJoinRequestRevertsForUnverifiedApplicant() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        publicPool.submitJoinRequest();
    }

    function testSubmitJoinRequestRejectsDuplicateOpenRequest() external {
        _verifyUser(outsider);

        vm.prank(outsider);
        publicPool.submitJoinRequest();

        vm.prank(outsider);
        vm.expectRevert(Errors.RequestAlreadyOpen.selector);
        publicPool.submitJoinRequest();
    }

    function testOnlyActiveMembersCanVoteAndMembersCanOnlyVoteOnce() external {
        _verifyUser(outsider);

        vm.prank(outsider);
        uint256 requestId = publicPool.submitJoinRequest();

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(member1);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(member1);
        vm.expectRevert(Errors.AlreadyVoted.selector);
        publicPool.voteJoinRequest(requestId, true);
    }

    function testApplicantCannotAcceptBeforeTwoThirdsQuorum() external {
        _verifyUser(outsider);

        vm.prank(member1);
        uint256 inviteId = publicPool.proposeInvite(member2);
        vm.prank(member1);
        publicPool.voteInvite(inviteId, true);
        vm.prank(member2);
        publicPool.acceptInvite(inviteId);

        vm.prank(outsider);
        uint256 requestId = publicPool.submitJoinRequest();

        vm.prank(member1);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        vm.expectRevert(Errors.ProposalNotPassed.selector);
        publicPool.acceptJoinRequest(requestId);
    }

    function testApplicantCanAcceptAfterQuorumAndStaysListedIfStillForming() external {
        _verifyUser(outsider);

        uint256 balanceBefore = token.balanceOf(outsider);

        vm.prank(outsider);
        uint256 requestId = publicPool.submitJoinRequest();

        vm.prank(member1);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        publicPool.acceptJoinRequest(requestId);

        (address applicant, uint256 yesVotes,, bool open) = publicPool.joinRequest(requestId);
        Types.PoolDiscoveryView memory listing = factory.recruitingPool(2);

        assertEq(applicant, outsider);
        assertEq(yesVotes, 1);
        assertFalse(open);
        assertTrue(publicPool.isMember(outsider));
        assertEq(publicPool.activeMemberCount(), 2);
        assertEq(token.balanceOf(outsider), balanceBefore);
        assertEq(uint256(publicPool.poolStatus()), uint256(Types.PoolStatus.Forming));
        assertTrue(listing.listed);
        assertEq(listing.activeMemberCount, 2);
    }

    function testInviteSnapshotIsFixedAtProposalTime() external {
        reputationAdapter.setScore(member1, 10);
        reputationAdapter.setScore(member2, 10);
        (ChainoraRoscaPool restrictedPool,) = _createPoolFor(member1, true, 3, 10);
        _approvePoolFor(address(restrictedPool), member2);

        vm.prank(member1);
        uint256 inviteId = restrictedPool.proposeInvite(member2);

        reputationAdapter.setScore(member2, 0);

        vm.prank(member1);
        restrictedPool.voteInvite(inviteId, true);

        uint256 balanceBefore = token.balanceOf(member2);
        vm.prank(member2);
        restrictedPool.acceptInvite(inviteId);

        assertEq(token.balanceOf(member2), balanceBefore);
        assertEq(restrictedPool.memberReputationSnapshot(member2), 10);
    }

    function testInviteRevertsWhenCandidateReputationBelowMinimum() external {
        reputationAdapter.setScore(member1, 11);
        reputationAdapter.setScore(member2, 9);
        (ChainoraRoscaPool restrictedPool,) = _createPoolFor(member1, true, 3, 10);

        vm.prank(member1);
        vm.expectRevert(Errors.InsufficientReputation.selector);
        restrictedPool.proposeInvite(member2);
    }

    function testJoinRequestSnapshotIsFixedAtRequestTime() external {
        _verifyUser(outsider);
        reputationAdapter.setScore(member1, 10);
        reputationAdapter.setScore(outsider, 10);

        (ChainoraRoscaPool restrictedPool,) = _createPoolFor(member1, true, 3, 10);
        _approvePoolFor(address(restrictedPool), outsider);

        vm.prank(outsider);
        uint256 requestId = restrictedPool.submitJoinRequest();

        reputationAdapter.setScore(outsider, 0);

        vm.prank(member1);
        restrictedPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        restrictedPool.acceptJoinRequest(requestId);

        assertEq(restrictedPool.memberReputationSnapshot(outsider), 10);
    }

    function testInviteAndJoinUseZeroSnapshotWithoutReputationAdapterAtZeroThreshold() external {
        _verifyUser(member2);
        _verifyUser(outsider);

        vm.prank(address(timelock));
        registry.setReputationAdapter(address(0));

        (ChainoraRoscaPool noAdapterPool,) = _createPoolFor(member1, true, 4, 0);
        _approvePoolFor(address(noAdapterPool), member2);
        _approvePoolFor(address(noAdapterPool), outsider);

        vm.prank(member1);
        uint256 inviteId = noAdapterPool.proposeInvite(member2);
        vm.prank(member1);
        noAdapterPool.voteInvite(inviteId, true);
        vm.prank(member2);
        noAdapterPool.acceptInvite(inviteId);

        vm.prank(outsider);
        uint256 requestId = noAdapterPool.submitJoinRequest();
        vm.prank(member1);
        noAdapterPool.voteJoinRequest(requestId, true);
        vm.prank(member2);
        noAdapterPool.voteJoinRequest(requestId, true);
        vm.prank(outsider);
        noAdapterPool.acceptJoinRequest(requestId);

        assertEq(noAdapterPool.memberReputationSnapshot(member1), 0);
        assertEq(noAdapterPool.memberReputationSnapshot(member2), 0);
        assertEq(noAdapterPool.memberReputationSnapshot(outsider), 0);
        assertEq(noAdapterPool.activeMemberCount(), 3);
    }

    function testJoinRequestRevertsWhenApplicantReputationBelowMinimum() external {
        _verifyUser(outsider);
        reputationAdapter.setScore(member1, 11);
        reputationAdapter.setScore(outsider, 9);

        (ChainoraRoscaPool restrictedPool,) = _createPoolFor(member1, true, 3, 10);
        _approvePoolFor(address(restrictedPool), outsider);

        vm.prank(outsider);
        vm.expectRevert(Errors.InsufficientReputation.selector);
        restrictedPool.submitJoinRequest();
    }

    function testCancelJoinRequestClosesItAndAllowsResubmit() external {
        _verifyUser(outsider);

        vm.prank(outsider);
        uint256 firstRequestId = publicPool.submitJoinRequest();

        vm.prank(outsider);
        publicPool.cancelJoinRequest(firstRequestId);

        (,,, bool open) = publicPool.joinRequest(firstRequestId);
        assertFalse(open);

        vm.prank(outsider);
        uint256 secondRequestId = publicPool.submitJoinRequest();

        assertEq(secondRequestId, firstRequestId + 1);
    }

    function testSubmitJoinRequestRevertsAfterVerificationIsRevoked() external {
        _verifyUser(outsider);

        vm.prank(address(timelock));
        deviceAdapter.revokeUser(outsider);

        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        publicPool.submitJoinRequest();
    }
}
