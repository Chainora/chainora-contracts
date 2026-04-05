// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {VoteMath} from "src/libraries/VoteMath.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";

abstract contract PauseRecoveryModule is PoolStorage {
    function _markDefaultAndPause(address caller, address defaultedMember) internal {
        _requireActiveMember(caller);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();
        if (!_isActiveMember[defaultedMember]) revert Errors.InvalidConfig();

        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.Collecting) revert Errors.InvalidState();
        if (block.timestamp < period.contributionDeadline) revert Errors.DeadlineNotReached();
        if (period.contributed[defaultedMember]) revert Errors.InvalidState();

        if (_memberDeposit[defaultedMember] < _contributionAmount) revert Errors.ContributionMissing();

        _memberDeposit[defaultedMember] -= _contributionAmount;
        period.contributed[defaultedMember] = true;
        period.totalContributed += _contributionAmount;

        _isActiveMember[defaultedMember] = false;
        _activeMemberCount -= 1;

        _poolStatus = Types.PoolStatus.Paused;
        _pauseVoteOpen = true;
        _pauseVoteRound += 1;
        _pauseYesVotes = 0;
        _defaultedMember = defaultedMember;

        emit ChainoraPoolPaused(defaultedMember, _currentCycle, _currentPeriod);
    }

    function _voteContinueAfterPause(address voter, bool support) internal {
        _requireActiveMember(voter);
        if (_poolStatus != Types.PoolStatus.Paused || !_pauseVoteOpen) revert Errors.InvalidState();
        if (_pauseVoted[_pauseVoteRound][voter]) revert Errors.AlreadyVoted();

        _pauseVoted[_pauseVoteRound][voter] = true;
        if (support) {
            _pauseYesVotes += 1;
        }

        emit ChainoraContinueVoted(voter, support, _pauseYesVotes, _activeMemberCount);

        if (VoteMath.isUnanimous(_pauseYesVotes, _activeMemberCount)) {
            _poolStatus = Types.PoolStatus.Active;
            _pauseVoteOpen = false;
            _defaultedMember = address(0);
            emit ChainoraPoolResumed(_currentCycle, _currentPeriod);
        }
    }
}
