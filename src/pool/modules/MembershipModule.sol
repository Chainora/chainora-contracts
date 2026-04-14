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
        _requireMember(proposer);
        if (candidate == address(0) || _isMember[candidate]) revert Errors.InvalidConfig();
        uint256 reputationSnapshot = _reputationScoreOf(candidate);
        if (reputationSnapshot < _minReputation) revert Errors.InsufficientReputation();

        proposalId = ++_inviteProposalCount;
        InviteProposal storage proposal = _inviteProposals[proposalId];
        proposal.candidate = candidate;
        proposal.reputationSnapshot = reputationSnapshot;
        proposal.open = true;

        emit ChainoraInviteProposed(proposalId, candidate, proposer);
    }

    function _voteInvite(address voter, uint256 proposalId, bool support) internal {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();
        _requireMember(voter);

        InviteProposal storage proposal = _inviteProposals[proposalId];
        if (!proposal.open) revert Errors.ProposalClosed();
        if (proposal.voted[voter]) revert Errors.AlreadyVoted();

        proposal.voted[voter] = true;
        if (support) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }

        emit ChainoraInviteVoted(proposalId, voter, support);
    }

    function _acceptInvite(address invitee, uint256 proposalId) internal {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();

        InviteProposal storage proposal = _inviteProposals[proposalId];
        if (!proposal.open) revert Errors.ProposalClosed();
        if (proposal.candidate != invitee) revert Errors.NotInvitee();

        if (!VoteMath.isTwoThirdsOrMore(proposal.yesVotes, _activeMemberCount)) {
            revert Errors.ProposalNotPassed();
        }

        proposal.open = false;
        emit ChainoraInviteAccepted(proposalId, invitee);
        _finalizeMemberAdmission(invitee, proposal.reputationSnapshot);
    }

    function _submitJoinRequest(address applicant) internal returns (uint256 requestId) {
        if (_poolStatus != Types.PoolStatus.Forming || !_publicRecruitment) revert Errors.InvalidState();
        if (_isMember[applicant]) revert Errors.InvalidConfig();
        if (_openJoinRequestOf[applicant] != 0) revert Errors.RequestAlreadyOpen();

        address deviceAdapter = _deviceAdapter();
        if (deviceAdapter != address(0)) {
            bool verified = IChainoraDeviceAdapter(deviceAdapter).isDeviceVerified(applicant);
            if (!verified) revert Errors.Unauthorized();
        }

        uint256 reputationSnapshot = _reputationScoreOf(applicant);
        if (reputationSnapshot < _minReputation) revert Errors.InsufficientReputation();

        requestId = ++_joinRequestCount;
        JoinRequest storage request = _joinRequests[requestId];
        request.applicant = applicant;
        request.reputationSnapshot = reputationSnapshot;
        request.open = true;
        _openJoinRequestOf[applicant] = requestId;

        emit ChainoraJoinRequestSubmitted(requestId, applicant);
    }

    function _voteJoinRequest(address voter, uint256 requestId, bool support) internal {
        if (_poolStatus != Types.PoolStatus.Forming || !_publicRecruitment) revert Errors.InvalidState();
        _requireActiveMember(voter);

        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) revert Errors.ProposalClosed();
        if (request.voted[voter]) revert Errors.AlreadyVoted();

        request.voted[voter] = true;
        if (support) {
            request.yesVotes += 1;
        } else {
            request.noVotes += 1;
        }

        emit ChainoraJoinRequestVoted(requestId, voter, support);
    }

    function _cancelJoinRequest(address applicant, uint256 requestId) internal {
        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) revert Errors.ProposalClosed();
        if (request.applicant != applicant) revert Errors.NotApplicant();

        request.open = false;
        delete _openJoinRequestOf[applicant];

        emit ChainoraJoinRequestCanceled(requestId, applicant);
    }

    function _acceptJoinRequest(address applicant, uint256 requestId) internal {
        if (_poolStatus != Types.PoolStatus.Forming || !_publicRecruitment) revert Errors.InvalidState();

        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) revert Errors.ProposalClosed();
        if (request.applicant != applicant) revert Errors.NotApplicant();

        if (!VoteMath.isTwoThirdsOrMore(request.yesVotes, _activeMemberCount)) {
            revert Errors.ProposalNotPassed();
        }

        request.open = false;
        delete _openJoinRequestOf[applicant];

        emit ChainoraJoinRequestAccepted(requestId, applicant);
        _finalizeMemberAdmission(applicant, request.reputationSnapshot);
    }

    function _finalizeMemberAdmission(address account, uint256 reputationSnapshot) private {
        uint256 openJoinRequestId = _openJoinRequestOf[account];
        if (openJoinRequestId != 0) {
            _joinRequests[openJoinRequestId].open = false;
            delete _openJoinRequestOf[account];
        }

        _addMember(account);
        _memberReputationSnapshot[account] = reputationSnapshot;

        if (_activeMemberCount == _targetMembers) {
            _startFirstCycle();
        }

        _syncRecruitingPool();
    }
}
