// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {IChainoraRoscaFactory} from "src/core/IChainoraRoscaFactory.sol";
import {IChainoraProtocolRegistry} from "src/core/IChainoraProtocolRegistry.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

abstract contract PoolStorage is Events {
    struct InviteProposal {
        address candidate;
        uint256 reputationSnapshot;
        uint256 quorumMemberCount;
        uint256 yesVotes;
        uint256 noVotes;
        bool open;
        mapping(address => bool) eligibleVoter;
        mapping(address => bool) voted;
    }

    struct JoinRequest {
        address applicant;
        uint256 reputationSnapshot;
        uint256 quorumMemberCount;
        uint256 yesVotes;
        uint256 noVotes;
        bool open;
        mapping(address => bool) eligibleVoter;
        mapping(address => bool) voted;
    }

    struct PeriodState {
        Types.PeriodStatus status;
        uint64 startAt;
        uint64 contributionDeadline;
        uint64 auctionDeadline;
        uint64 payoutDeadline;
        address recipient;
        address bestBidder;
        uint256 bestDiscount;
        uint256 totalContributed;
        uint256 payoutAmount;
        bool payoutClaimed;
        bytes32 reputationSnapshotId;
        mapping(address => bool) contributed;
    }

    bool internal _initialized;

    uint256 internal _poolId;
    address internal _factory;
    address internal _registry;
    address internal _stablecoin;
    address internal _creator;
    bool internal _publicRecruitment;

    uint256 internal _contributionAmount;
    uint256 internal _minReputation;
    uint16 internal _targetMembers;
    uint32 internal _periodDuration;
    uint32 internal _contributionWindow;
    uint32 internal _auctionWindow;
    uint8 internal _maxCycles;

    Types.PoolStatus internal _poolStatus;

    uint256 internal _currentCycle;
    uint256 internal _currentPeriod;
    bool internal _cycleCompleted;

    address[] internal _members;
    mapping(address => bool) internal _isMember;
    mapping(address => bool) internal _isActiveMember;
    mapping(address => uint256) internal _memberReputationSnapshot;
    uint256 internal _activeMemberCount;

    uint256 internal _inviteProposalCount;
    mapping(uint256 => InviteProposal) internal _inviteProposals;
    uint256[] internal _openInviteProposalIds;
    mapping(uint256 => uint256) internal _openInviteProposalIndexPlusOne;
    uint256 internal _joinRequestCount;
    mapping(uint256 => JoinRequest) internal _joinRequests;
    uint256[] internal _openJoinRequestIds;
    mapping(uint256 => uint256) internal _openJoinRequestIndexPlusOne;
    mapping(address => uint256) internal _openJoinRequestOf;

    mapping(uint256 => mapping(uint256 => PeriodState)) internal _periods;
    mapping(uint256 => mapping(address => bool)) internal _hasReceivedInCycle;
    mapping(uint256 => uint256) internal _cycleMemberCount;

    mapping(address => uint256) internal _claimableYield;
    mapping(address => uint256) internal _claimableArchiveRefund;

    uint256 internal _extendVoteRound;
    mapping(uint256 => mapping(address => bool)) internal _extendVoted;
    bool internal _extendVoteOpen;
    uint64 internal _extendVoteDeadline;
    uint256 internal _extendYesVotes;

    mapping(address => bool) internal _leftArchive;

    function _requireMember(address account) internal view {
        if (!_isMember[account]) revert Errors.NotMember();
    }

    function _requireActiveMember(address account) internal view {
        if (!_isActiveMember[account]) revert Errors.NotActiveMember();
    }

    function _activateMember(address account) internal {
        if (_isActiveMember[account]) revert Errors.InvalidConfig();
        if (!_isMember[account]) {
            _isMember[account] = true;
            _members.push(account);
        }
        _isActiveMember[account] = true;
        _activeMemberCount += 1;
    }

    function _deactivateMember(address account) internal {
        if (!_isActiveMember[account]) revert Errors.NotActiveMember();
        _isActiveMember[account] = false;
        _activeMemberCount -= 1;
    }

    function _currentPeriodStorage() internal view returns (PeriodState storage period) {
        period = _periods[_currentCycle][_currentPeriod];
    }

    function _openPeriod(uint256 cycleId, uint256 periodId) internal {
        PeriodState storage period = _periods[cycleId][periodId];
        if (period.startAt != 0) revert Errors.InvalidState();

        uint64 startAt = uint64(block.timestamp);
        period.status = Types.PeriodStatus.Collecting;
        period.startAt = startAt;
        period.contributionDeadline = startAt + uint64(_contributionWindow);
        period.auctionDeadline = 0;
        period.payoutDeadline = 0;
    }

    function _startFirstCycle() internal {
        _poolStatus = Types.PoolStatus.Active;
        _currentCycle = 1;
        _currentPeriod = 1;
        _cycleCompleted = false;
        _extendVoteOpen = false;
        _extendVoteDeadline = 0;
        _extendYesVotes = 0;
        _cycleMemberCount[1] = _activeMemberCount;
        _openPeriod(1, 1);
        emit ChainoraPoolActivated(1, _periods[1][1].startAt);
    }

    function _startNextCycle() internal {
        if (_currentCycle >= _maxCycles) {
            _poolStatus = Types.PoolStatus.Archived;
            emit ChainoraPoolArchived();
            return;
        }

        _currentCycle += 1;
        _currentPeriod = 1;
        _cycleCompleted = false;
        _extendVoteOpen = false;
        _extendVoteDeadline = 0;
        _extendYesVotes = 0;
        _cycleMemberCount[_currentCycle] = _activeMemberCount;
        _openPeriod(_currentCycle, 1);
        emit ChainoraPoolActivated(_currentCycle, _periods[_currentCycle][1].startAt);
    }

    function _payoutWindow() internal view returns (uint32) {
        return _periodDuration - _contributionWindow - _auctionWindow;
    }

    function _activeMembersList() internal view returns (address[] memory activeMembers) {
        activeMembers = new address[](_activeMemberCount);
        uint256 cursor;
        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member]) {
                activeMembers[cursor] = member;
                cursor += 1;
                if (cursor == _activeMemberCount) break;
            }
        }
    }

    function _allActiveContributed(PeriodState storage period) internal view returns (bool) {
        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member] && !period.contributed[member]) {
                return false;
            }
        }
        return true;
    }

    function _allActiveMembersReceivedInCurrentCycle() internal view returns (bool) {
        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member] && !_hasReceivedInCycle[_currentCycle][member]) {
                return false;
            }
        }
        return true;
    }

    function _reputationAdapter() internal view returns (address) {
        return IChainoraProtocolRegistry(_registry).reputationAdapter();
    }

    function _stakingAdapter() internal view returns (address) {
        return IChainoraProtocolRegistry(_registry).stakingAdapter();
    }

    function _deviceAdapter() internal view returns (address) {
        return IChainoraProtocolRegistry(_registry).deviceAdapter();
    }

    function _reputationScoreOf(address account) internal view returns (uint256) {
        address reputationAdapter = _reputationAdapter();
        if (reputationAdapter == address(0)) return 0;
        return IChainoraReputationAdapter(reputationAdapter).scoreOf(account);
    }

    function _syncRecruitingPool() internal {
        if (_publicRecruitment) {
            IChainoraRoscaFactory(_factory).syncRecruitingPool();
        }
    }

    function _snapshotInviteEligibleVoters(uint256 proposalId) internal {
        InviteProposal storage proposal = _inviteProposals[proposalId];
        proposal.quorumMemberCount = _activeMemberCount;

        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member]) {
                proposal.eligibleVoter[member] = true;
            }
        }
    }

    function _snapshotJoinRequestEligibleVoters(uint256 requestId) internal {
        JoinRequest storage request = _joinRequests[requestId];
        request.quorumMemberCount = _activeMemberCount;

        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member]) {
                request.eligibleVoter[member] = true;
            }
        }
    }

    function _trackOpenInviteProposal(uint256 proposalId) internal {
        if (_openInviteProposalIndexPlusOne[proposalId] != 0) return;

        _openInviteProposalIds.push(proposalId);
        _openInviteProposalIndexPlusOne[proposalId] = _openInviteProposalIds.length;
    }

    function _trackOpenJoinRequest(uint256 requestId) internal {
        if (_openJoinRequestIndexPlusOne[requestId] != 0) return;

        _openJoinRequestIds.push(requestId);
        _openJoinRequestIndexPlusOne[requestId] = _openJoinRequestIds.length;
    }

    function _closeInviteProposal(uint256 proposalId) internal {
        InviteProposal storage proposal = _inviteProposals[proposalId];
        if (!proposal.open) return;

        proposal.open = false;
        _removeOpenInviteProposal(proposalId);
    }

    function _closeJoinRequest(uint256 requestId) internal {
        JoinRequest storage request = _joinRequests[requestId];
        if (!request.open) return;

        request.open = false;
        if (_openJoinRequestOf[request.applicant] == requestId) {
            delete _openJoinRequestOf[request.applicant];
        }
        _removeOpenJoinRequest(requestId);
    }

    function _closeAllOpenMembershipItems() internal {
        while (_openInviteProposalIds.length != 0) {
            uint256 proposalId = _openInviteProposalIds[_openInviteProposalIds.length - 1];
            _inviteProposals[proposalId].open = false;
            delete _openInviteProposalIndexPlusOne[proposalId];
            _openInviteProposalIds.pop();
        }

        while (_openJoinRequestIds.length != 0) {
            uint256 requestId = _openJoinRequestIds[_openJoinRequestIds.length - 1];
            JoinRequest storage request = _joinRequests[requestId];
            request.open = false;
            if (_openJoinRequestOf[request.applicant] == requestId) {
                delete _openJoinRequestOf[request.applicant];
            }
            delete _openJoinRequestIndexPlusOne[requestId];
            _openJoinRequestIds.pop();
        }
    }

    function _removeOpenInviteProposal(uint256 proposalId) private {
        uint256 indexPlusOne = _openInviteProposalIndexPlusOne[proposalId];
        if (indexPlusOne == 0) return;

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = _openInviteProposalIds.length - 1;
        if (index != lastIndex) {
            uint256 movedProposalId = _openInviteProposalIds[lastIndex];
            _openInviteProposalIds[index] = movedProposalId;
            _openInviteProposalIndexPlusOne[movedProposalId] = indexPlusOne;
        }

        _openInviteProposalIds.pop();
        delete _openInviteProposalIndexPlusOne[proposalId];
    }

    function _removeOpenJoinRequest(uint256 requestId) private {
        uint256 indexPlusOne = _openJoinRequestIndexPlusOne[requestId];
        if (indexPlusOne == 0) return;

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = _openJoinRequestIds.length - 1;
        if (index != lastIndex) {
            uint256 movedRequestId = _openJoinRequestIds[lastIndex];
            _openJoinRequestIds[index] = movedRequestId;
            _openJoinRequestIndexPlusOne[movedRequestId] = indexPlusOne;
        }

        _openJoinRequestIds.pop();
        delete _openJoinRequestIndexPlusOne[requestId];
    }
}
