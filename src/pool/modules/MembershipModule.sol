// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VoteMath} from "src/libraries/VoteMath.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";

abstract contract MembershipModule is PoolStorage {
    using SafeTransferLibExt for address;

    function _proposeInvite(address proposer, address candidate) internal returns (uint256 proposalId) {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();
        _requireMember(proposer);
        if (candidate == address(0) || _isMember[candidate]) revert Errors.InvalidConfig();

        proposalId = ++_inviteProposalCount;
        InviteProposal storage proposal = _inviteProposals[proposalId];
        proposal.candidate = candidate;
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

    function _acceptInviteAndLockDeposit(address invitee, uint256 proposalId) internal {
        if (_poolStatus != Types.PoolStatus.Forming) revert Errors.InvalidState();

        InviteProposal storage proposal = _inviteProposals[proposalId];
        if (!proposal.open) revert Errors.ProposalClosed();
        if (proposal.candidate != invitee) revert Errors.NotInvitee();

        if (!VoteMath.isTwoThirdsOrMore(proposal.yesVotes, _activeMemberCount)) {
            revert Errors.ProposalNotPassed();
        }

        _stablecoin.safeTransferFrom(invitee, address(this), _contributionAmount);

        proposal.open = false;
        _addMember(invitee);
        _memberDeposit[invitee] += _contributionAmount;

        emit ChainoraInviteAccepted(proposalId, invitee);

        if (_activeMemberCount == _targetMembers) {
            _startFirstCycle();
        }
    }
}
