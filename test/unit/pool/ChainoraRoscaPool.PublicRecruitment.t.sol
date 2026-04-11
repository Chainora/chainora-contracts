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
        publicPool.acceptInviteAndLockDeposit(inviteId);

        vm.prank(outsider);
        uint256 requestId = publicPool.submitJoinRequest();

        vm.prank(member1);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        vm.expectRevert(Errors.ProposalNotPassed.selector);
        publicPool.acceptJoinRequestAndLockDeposit(requestId);
    }

    function testApplicantCanAcceptAfterQuorumAndStaysListedIfStillForming() external {
        _verifyUser(outsider);

        vm.prank(outsider);
        uint256 requestId = publicPool.submitJoinRequest();

        vm.prank(member1);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        publicPool.acceptJoinRequestAndLockDeposit(requestId);

        (address applicant, uint256 yesVotes,, bool open) = publicPool.joinRequest(requestId);
        Types.PoolDiscoveryView memory listing = factory.recruitingPool(2);

        assertEq(applicant, outsider);
        assertEq(yesVotes, 1);
        assertFalse(open);
        assertTrue(publicPool.isMember(outsider));
        assertEq(publicPool.activeMemberCount(), 2);
        assertEq(publicPool.memberDeposit(outsider), CONTRIBUTION);
        assertEq(uint256(publicPool.poolStatus()), uint256(Types.PoolStatus.Forming));
        assertTrue(listing.listed);
        assertEq(listing.activeMemberCount, 2);
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
