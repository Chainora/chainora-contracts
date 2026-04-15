// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {Errors} from "src/libraries/Errors.sol";
import {VoteMath} from "src/libraries/VoteMath.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";

abstract contract ExtensionModule is PoolStorage {
    using SafeTransferLibExt for address;

    function _voteExtendCycle(address voter, bool support) internal {
        _requireActiveMember(voter);
        if (_poolStatus != Types.PoolStatus.Active || !_cycleCompleted || !_extendVoteOpen) {
            revert Errors.InvalidState();
        }
        if (_extendVoted[_extendVoteRound][voter]) revert Errors.AlreadyVoted();

        _extendVoted[_extendVoteRound][voter] = true;

        if (!support) {
            _extendVoteOpen = false;
            _poolStatus = Types.PoolStatus.Archived;
            emit ChainoraExtendVoted(voter, false, _extendYesVotes, _activeMemberCount);
            emit ChainoraPoolArchived();
            return;
        }

        _extendYesVotes += 1;
        emit ChainoraExtendVoted(voter, true, _extendYesVotes, _activeMemberCount);

        if (VoteMath.isUnanimous(_extendYesVotes, _activeMemberCount)) {
            _extendVoteOpen = false;
            _startNextCycle();
        }
    }

    function _archive(address caller) internal {
        _requireActiveMember(caller);

        if (_poolStatus == Types.PoolStatus.Active && _cycleCompleted && _extendVoteOpen) {
            _extendVoteOpen = false;
            _poolStatus = Types.PoolStatus.Archived;
            emit ChainoraPoolArchived();
            return;
        }

        if (_poolStatus == Types.PoolStatus.Archived) {
            return;
        }

        revert Errors.InvalidState();
    }

    function _claimArchiveRefund(address member) internal {
        _requireMember(member);
        if (_poolStatus != Types.PoolStatus.Archived) revert Errors.PoolNotArchived();

        uint256 amount = _claimableArchiveRefund[member];
        if (amount == 0) revert Errors.PayoutUnavailable();

        _claimableArchiveRefund[member] = 0;
        _stablecoin.safeTransfer(member, amount);

        emit ChainoraArchiveRefundClaimed(member, amount);
    }

    function _leaveAfterArchive(address member) internal {
        _requireMember(member);
        if (_poolStatus != Types.PoolStatus.Archived) revert Errors.PoolNotArchived();
        if (_leftArchive[member]) revert Errors.AlreadyLeft();
        if (_claimableYield[member] != 0 || _claimableArchiveRefund[member] != 0) revert Errors.InvalidState();

        _leftArchive[member] = true;
        emit ChainoraLeftPool(member);
    }
}
