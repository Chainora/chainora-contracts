// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VoteMath} from "src/libraries/VoteMath.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";

abstract contract MembershipModule is PoolStorage {
    function _proposeInvite(address proposer, address candidate) internal returns (uint256 proposalId) {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();
        _requireActiveMember(proposer);
        if (candidate == address(0) || _isActiveMember[candidate]) revert Errors.InvalidConfig();
        _requireDeviceVerified(candidate);
        uint256 reputationSnapshot = _reputationScoreOf(candidate);
        if (reputationSnapshot < _minReputation) revert Errors.InsufficientReputation();

        proposalId = ++_inviteProposalCount;
        InviteProposal storage proposal = _inviteProposals[proposalId];
        proposal.candidate = candidate;
        proposal.reputationSnapshot = reputationSnapshot;
        proposal.open = true;
        _snapshotInviteEligibleVoters(proposalId);
        _trackOpenInviteProposal(proposalId);

        emit ChainoraInviteProposed(proposalId, candidate, proposer);
    }

    function _voteInvite(address voter, uint256 proposalId, bool support) internal {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();
        _requireActiveMember(voter);

        InviteProposal storage proposal = _inviteProposals[proposalId];
        if (!proposal.open) revert Errors.ProposalClosed();
        if (!proposal.eligibleVoter[voter]) revert Errors.Unauthorized();

        _castInviteVote(proposal, proposalId, voter, support);
    }

    function _acceptInvite(address invitee, uint256 proposalId) internal {
        InviteProposal storage proposal = _inviteProposals[proposalId];
        if (!proposal.open) revert Errors.ProposalClosed();
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();
        if (proposal.candidate != invitee) revert Errors.NotInvitee();

        if (!VoteMath.isTwoThirdsOrMore(proposal.yesVotes, proposal.quorumMemberCount)) {
            revert Errors.ProposalNotPassed();
        }

        _closeInviteProposal(proposalId);
        emit ChainoraInviteAccepted(proposalId, invitee);
        _finalizeMemberAdmission(invitee, proposal.reputationSnapshot);
    }

    function _submitJoinRequest(address applicant) internal returns (uint256 requestId) {
        if (_poolStatus != Types.PoolStatus.Forming || !_publicRecruitment) revert Errors.InvalidState();
        if (_isActiveMember[applicant]) revert Errors.InvalidConfig();
        if (_openJoinRequestOf[applicant] != 0) revert Errors.RequestAlreadyOpen();

        _requireDeviceVerified(applicant);

        uint256 reputationSnapshot = _reputationScoreOf(applicant);
        if (reputationSnapshot < _minReputation) revert Errors.InsufficientReputation();

        requestId = ++_joinRequestCount;
        JoinRequest storage request = _joinRequests[requestId];
        request.applicant = applicant;
        request.reputationSnapshot = reputationSnapshot;
        request.open = true;
        _openJoinRequestOf[applicant] = requestId;
        _snapshotJoinRequestEligibleVoters(requestId);
        _trackOpenJoinRequest(requestId);

        emit ChainoraJoinRequestSubmitted(requestId, applicant);
    }

    function _voteJoinRequest(address voter, uint256 requestId, bool support) internal {
        if (_poolStatus != Types.PoolStatus.Forming || !_publicRecruitment) revert Errors.InvalidState();
        _requireActiveMember(voter);

        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) revert Errors.ProposalClosed();
        if (!request.eligibleVoter[voter]) revert Errors.Unauthorized();

        _castJoinRequestVote(request, requestId, voter, support);
    }

    function _cancelJoinRequest(address applicant, uint256 requestId) internal {
        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) revert Errors.ProposalClosed();
        if (request.applicant != applicant) revert Errors.NotApplicant();

        _closeJoinRequest(requestId);
        emit ChainoraJoinRequestCanceled(requestId, applicant);
    }

    function _acceptJoinRequest(address applicant, uint256 requestId) internal {
        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) revert Errors.ProposalClosed();
        if (_poolStatus != Types.PoolStatus.Forming || !_publicRecruitment) revert Errors.InvalidState();
        if (request.applicant != applicant) revert Errors.NotApplicant();

        if (!VoteMath.isTwoThirdsOrMore(request.yesVotes, request.quorumMemberCount)) {
            revert Errors.ProposalNotPassed();
        }

        _closeJoinRequest(requestId);
        emit ChainoraJoinRequestAccepted(requestId, applicant);
        _finalizeMemberAdmission(applicant, request.reputationSnapshot);
    }

    function _leaveDuringForming(address member) internal {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();
        _requireActiveMember(member);

        _autoSupportOpenInviteProposals(member);
        _autoSupportOpenJoinRequests(member);
        _deactivateMember(member);

        emit ChainoraLeftPool(member);

        if (_activeMemberCount == 0) {
            _closeAllOpenMembershipItems();
            _poolStatus = Types.PoolStatus.Archived;
            emit ChainoraPoolArchived();
        }

        _syncRecruitingPool();
    }

    function _finalizeMemberAdmission(address account, uint256 reputationSnapshot) private {
        _requireDeviceVerified(account);

        uint256 openJoinRequestId = _openJoinRequestOf[account];
        if (openJoinRequestId != 0) {
            _closeJoinRequest(openJoinRequestId);
        }

        _activateMember(account);
        _memberReputationSnapshot[account] = reputationSnapshot;

        if (_activeMemberCount == _targetMembers) {
            _closeAllOpenMembershipItems();
            _startFirstCycle();
        }

        _syncRecruitingPool();
    }

    function _castInviteVote(InviteProposal storage proposal, uint256 proposalId, address voter, bool support) private {
        if (proposal.voted[voter]) revert Errors.AlreadyVoted();

        proposal.voted[voter] = true;
        if (support) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }

        emit ChainoraInviteVoted(proposalId, voter, support);
    }

    function _castJoinRequestVote(JoinRequest storage request, uint256 requestId, address voter, bool support) private {
        if (request.voted[voter]) revert Errors.AlreadyVoted();

        request.voted[voter] = true;
        if (support) {
            request.yesVotes += 1;
        } else {
            request.noVotes += 1;
        }

        emit ChainoraJoinRequestVoted(requestId, voter, support);
    }

    function _autoSupportOpenInviteProposals(address member) private {
        uint256 len = _openInviteProposalIds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 proposalId = _openInviteProposalIds[i];
            InviteProposal storage proposal = _inviteProposals[proposalId];
            if (proposal.eligibleVoter[member] && !proposal.voted[member]) {
                _castInviteVote(proposal, proposalId, member, true);
            }
        }
    }

    function _autoSupportOpenJoinRequests(address member) private {
        uint256 len = _openJoinRequestIds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 requestId = _openJoinRequestIds[i];
            JoinRequest storage request = _joinRequests[requestId];
            if (request.eligibleVoter[member] && !request.voted[member]) {
                _castJoinRequestVote(request, requestId, member, true);
            }
        }
    }

    function _requireDeviceVerified(address account) private view {
        address deviceAdapter = _deviceAdapter();
        if (deviceAdapter == address(0)) return;

        bool verified = IChainoraDeviceAdapter(deviceAdapter).isDeviceVerified(account);
        if (!verified) revert Errors.Unauthorized();
    }
}
