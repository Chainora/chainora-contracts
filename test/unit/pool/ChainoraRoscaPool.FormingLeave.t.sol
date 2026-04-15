// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolFormingLeaveTest is ChainoraTestBase, Events {
    function setUp() external {
        _setUpProtocolAndPool();
        _verifyUser(outsider);
    }

    function testLeaveDuringFormingUpdatesMembershipAndRecruitingListing() external {
        (ChainoraRoscaPool formingPool, uint256 poolId) = _createFormingPool(true, 4);
        _inviteAndAccept(formingPool, member1);

        vm.expectEmit(true, false, false, false, address(formingPool));
        emit ChainoraLeftPool(member1);

        vm.prank(member1);
        formingPool.leaveDuringForming();

        Types.PoolDiscoveryView memory listing = factory.recruitingPool(poolId);

        assertTrue(formingPool.isMember(member1));
        assertFalse(formingPool.isActiveMember(member1));
        assertEq(formingPool.activeMemberCount(), 1);
        assertTrue(listing.listed);
        assertEq(listing.activeMemberCount, 1);

        vm.prank(member1);
        vm.expectRevert(Errors.NotActiveMember.selector);
        formingPool.proposeInvite(member2);

        vm.prank(outsider);
        uint256 requestId = formingPool.submitJoinRequest();

        vm.prank(member1);
        vm.expectRevert(Errors.NotActiveMember.selector);
        formingPool.voteJoinRequest(requestId, true);

        vm.prank(member1);
        vm.expectRevert(Errors.NotActiveMember.selector);
        formingPool.archive();
    }

    function testLeaveDuringFormingAutoArchivesWhenLastActiveMemberLeavesAndClosesOpenItems() external {
        (ChainoraRoscaPool formingPool, uint256 poolId) = _createFormingPool(true, 3);

        vm.prank(creator);
        uint256 inviteId = formingPool.proposeInvite(member1);

        vm.prank(outsider);
        uint256 requestId = formingPool.submitJoinRequest();

        vm.expectEmit(true, true, false, true, address(formingPool));
        emit ChainoraInviteVoted(inviteId, creator, true);
        vm.expectEmit(true, true, false, true, address(formingPool));
        emit ChainoraJoinRequestVoted(requestId, creator, true);
        vm.expectEmit(true, false, false, false, address(formingPool));
        emit ChainoraLeftPool(creator);
        vm.expectEmit(false, false, false, false, address(formingPool));
        emit ChainoraPoolArchived();

        vm.prank(creator);
        formingPool.leaveDuringForming();

        (,, uint256 inviteNoVotes, bool inviteOpen) = formingPool.inviteProposal(inviteId);
        (, uint256 joinYesVotes, uint256 joinNoVotes, bool joinOpen) = formingPool.joinRequest(requestId);
        Types.PoolDiscoveryView memory listing = factory.recruitingPool(poolId);

        assertEq(inviteNoVotes, 0);
        assertEq(joinYesVotes, 1);
        assertEq(joinNoVotes, 0);
        assertFalse(inviteOpen);
        assertFalse(joinOpen);
        assertEq(uint256(formingPool.poolStatus()), uint256(Types.PoolStatus.Archived));
        assertEq(formingPool.activeMemberCount(), 0);
        assertEq(factory.recruitingPoolCount(), 0);
        assertFalse(listing.listed);
        assertEq(uint256(listing.poolStatus), uint256(Types.PoolStatus.Archived));

        vm.prank(member1);
        vm.expectRevert(Errors.ProposalClosed.selector);
        formingPool.acceptInvite(inviteId);

        vm.prank(outsider);
        vm.expectRevert(Errors.ProposalClosed.selector);
        formingPool.acceptJoinRequest(requestId);
    }

    function testFormerMemberCanRejoinWithoutDuplicatingMembersAndSnapshotRefreshes() external {
        reputationAdapter.setScore(member1, 7);
        (ChainoraRoscaPool formingPool,) = _createFormingPool(false, 4);
        _inviteAndAccept(formingPool, member1);

        assertEq(formingPool.memberReputationSnapshot(member1), 7);

        vm.prank(member1);
        formingPool.leaveDuringForming();

        reputationAdapter.setScore(member1, 12);

        vm.prank(creator);
        uint256 rejoinInviteId = formingPool.proposeInvite(member1);
        vm.prank(creator);
        formingPool.voteInvite(rejoinInviteId, true);
        vm.prank(member1);
        formingPool.acceptInvite(rejoinInviteId);

        address[] memory members = formingPool.members();
        assertEq(members.length, 2);
        assertEq(members[0], creator);
        assertEq(members[1], member1);
        assertEq(formingPool.activeMemberCount(), 2);
        assertEq(formingPool.memberReputationSnapshot(member1), 12);
    }

    function testLeaveDuringFormingAutoSupportsOpenInviteUsingSnapshotQuorum() external {
        (ChainoraRoscaPool formingPool,) = _createFormingPool(false, 4);
        _inviteAndAccept(formingPool, member1);

        vm.prank(creator);
        uint256 inviteId = formingPool.proposeInvite(outsider);

        vm.expectEmit(true, true, false, true, address(formingPool));
        emit ChainoraInviteVoted(inviteId, member1, true);
        vm.expectEmit(true, false, false, false, address(formingPool));
        emit ChainoraLeftPool(member1);

        vm.prank(member1);
        formingPool.leaveDuringForming();

        (, uint256 yesVotes, uint256 noVotes, bool open) = formingPool.inviteProposal(inviteId);
        assertEq(yesVotes, 1);
        assertEq(noVotes, 0);
        assertTrue(open);

        vm.prank(outsider);
        vm.expectRevert(Errors.ProposalNotPassed.selector);
        formingPool.acceptInvite(inviteId);

        vm.prank(creator);
        formingPool.voteInvite(inviteId, true);

        vm.prank(outsider);
        formingPool.acceptInvite(inviteId);

        assertTrue(formingPool.isActiveMember(outsider));
    }

    function testLeaveDuringFormingKeepsExistingJoinRequestVoteTallyWhenMemberAlreadyVoted() external {
        (ChainoraRoscaPool formingPool,) = _createFormingPool(true, 4);
        _inviteAndAccept(formingPool, member1);

        vm.prank(outsider);
        uint256 requestId = formingPool.submitJoinRequest();

        vm.prank(member1);
        formingPool.voteJoinRequest(requestId, false);

        vm.prank(member1);
        formingPool.leaveDuringForming();

        (, uint256 yesVotes, uint256 noVotes, bool open) = formingPool.joinRequest(requestId);
        assertEq(yesVotes, 0);
        assertEq(noVotes, 1);
        assertTrue(open);

        vm.prank(creator);
        formingPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        vm.expectRevert(Errors.ProposalNotPassed.selector);
        formingPool.acceptJoinRequest(requestId);
    }

    function testPoolFullViaAcceptInviteClosesRemainingInvites() external {
        (ChainoraRoscaPool formingPool,) = _createFormingPool(false, 2);

        vm.prank(creator);
        uint256 firstInviteId = formingPool.proposeInvite(member1);
        vm.prank(creator);
        formingPool.voteInvite(firstInviteId, true);

        vm.prank(creator);
        uint256 secondInviteId = formingPool.proposeInvite(member2);
        vm.prank(creator);
        formingPool.voteInvite(secondInviteId, true);

        vm.prank(member1);
        formingPool.acceptInvite(firstInviteId);

        (,,, bool secondInviteOpen) = formingPool.inviteProposal(secondInviteId);
        assertEq(uint256(formingPool.poolStatus()), uint256(Types.PoolStatus.Active));
        assertFalse(secondInviteOpen);

        vm.prank(member2);
        vm.expectRevert(Errors.ProposalClosed.selector);
        formingPool.acceptInvite(secondInviteId);
    }

    function testPoolFullViaAcceptJoinRequestClosesRemainingRequests() external {
        (ChainoraRoscaPool formingPool, uint256 poolId) = _createFormingPool(true, 2);

        vm.prank(outsider);
        uint256 firstRequestId = formingPool.submitJoinRequest();
        vm.prank(member2);
        uint256 secondRequestId = formingPool.submitJoinRequest();

        vm.prank(creator);
        formingPool.voteJoinRequest(firstRequestId, true);
        vm.prank(creator);
        formingPool.voteJoinRequest(secondRequestId, true);

        vm.prank(outsider);
        formingPool.acceptJoinRequest(firstRequestId);

        (,,, bool secondRequestOpen) = formingPool.joinRequest(secondRequestId);
        Types.PoolDiscoveryView memory listing = factory.recruitingPool(poolId);

        assertEq(factory.recruitingPoolCount(), 0);
        assertEq(uint256(formingPool.poolStatus()), uint256(Types.PoolStatus.Active));
        assertFalse(secondRequestOpen);
        assertFalse(listing.listed);

        vm.prank(member2);
        vm.expectRevert(Errors.ProposalClosed.selector);
        formingPool.acceptJoinRequest(secondRequestId);
    }

    function _createFormingPool(bool publicRecruitment, uint16 targetMembers)
        internal
        returns (ChainoraRoscaPool newPool, uint256 newPoolId)
    {
        (newPool, newPoolId) = _createPoolFor(creator, publicRecruitment, targetMembers);
        _approvePoolFor(address(newPool), member1);
        _approvePoolFor(address(newPool), member2);
        _approvePoolFor(address(newPool), outsider);
    }

    function _inviteAndAccept(ChainoraRoscaPool targetPool, address candidate) internal {
        vm.prank(creator);
        uint256 inviteId = targetPool.proposeInvite(candidate);
        vm.prank(creator);
        targetPool.voteInvite(inviteId, true);
        vm.prank(candidate);
        targetPool.acceptInvite(inviteId);
    }
}
