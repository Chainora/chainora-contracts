// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {PeriodMath} from "src/libraries/PeriodMath.sol";
import {IChainoraRoscaFactory} from "src/core/IChainoraRoscaFactory.sol";
import {IChainoraProtocolRegistry} from "src/core/IChainoraProtocolRegistry.sol";

abstract contract PoolStorage is Events {
    struct InviteProposal {
        address candidate;
        uint256 yesVotes;
        uint256 noVotes;
        bool open;
        mapping(address => bool) voted;
    }

    struct JoinRequest {
        address applicant;
        uint256 yesVotes;
        uint256 noVotes;
        bool open;
        mapping(address => bool) voted;
    }

    struct PeriodState {
        Types.PeriodStatus status;
        uint64 startAt;
        uint64 contributionDeadline;
        uint64 auctionDeadline;
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
    mapping(address => uint256) internal _memberDeposit;
    uint256 internal _activeMemberCount;

    uint256 internal _inviteProposalCount;
    mapping(uint256 => InviteProposal) internal _inviteProposals;
    uint256 internal _joinRequestCount;
    mapping(uint256 => JoinRequest) internal _joinRequests;
    mapping(address => uint256) internal _openJoinRequestOf;

    mapping(uint256 => mapping(uint256 => PeriodState)) internal _periods;
    mapping(uint256 => mapping(address => bool)) internal _hasReceivedInCycle;
    mapping(uint256 => uint256) internal _cycleMemberCount;

    mapping(address => uint256) internal _claimableYield;

    uint256 internal _pauseVoteRound;
    mapping(uint256 => mapping(address => bool)) internal _pauseVoted;
    bool internal _pauseVoteOpen;
    uint256 internal _pauseYesVotes;
    address internal _defaultedMember;

    uint256 internal _extendVoteRound;
    mapping(uint256 => mapping(address => bool)) internal _extendVoted;
    bool internal _extendVoteOpen;
    uint256 internal _extendYesVotes;

    mapping(address => bool) internal _leftArchive;

    function _requireMember(address account) internal view {
        if (!_isMember[account]) revert Errors.NotMember();
    }

    function _requireActiveMember(address account) internal view {
        if (!_isActiveMember[account]) revert Errors.NotActiveMember();
    }

    function _addMember(address account) internal {
        if (_isMember[account]) revert Errors.InvalidConfig();
        _isMember[account] = true;
        _isActiveMember[account] = true;
        _members.push(account);
        _activeMemberCount += 1;
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
        period.contributionDeadline = PeriodMath.contributionDeadline(startAt, _contributionWindow);
        period.auctionDeadline = PeriodMath.auctionDeadline(startAt, _contributionWindow, _auctionWindow);
    }

    function _startFirstCycle() internal {
        _poolStatus = Types.PoolStatus.Active;
        _currentCycle = 1;
        _currentPeriod = 1;
        _cycleCompleted = false;
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
        _cycleMemberCount[_currentCycle] = _activeMemberCount;
        _openPeriod(_currentCycle, 1);
        emit ChainoraPoolActivated(_currentCycle, _periods[_currentCycle][1].startAt);
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

    function _syncRecruitingPool() internal {
        if (_publicRecruitment) {
            IChainoraRoscaFactory(_factory).syncRecruitingPool();
        }
    }
}
