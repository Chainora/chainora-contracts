// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

abstract contract RuntimeSyncModule is PoolStorage {
    using SafeTransferLibExt for address;

    uint32 internal constant EXTEND_VOTE_DURATION = 1 days;

    function _syncRuntimePhase(address caller) internal {
        _requireActiveMember(caller);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) return;

        while (true) {
            PeriodState storage period = _currentPeriodStorage();

            if (period.status == Types.PeriodStatus.Collecting) {
                if (block.timestamp < period.contributionDeadline || !_allActiveContributed(period)) {
                    break;
                }

                _advanceCollectingToAuction(period);
                continue;
            }

            if (period.status == Types.PeriodStatus.Auction) {
                if (period.auctionDeadline == 0 || block.timestamp < period.auctionDeadline) {
                    break;
                }

                _selectRecipientAndOpenPayout(period);
                continue;
            }

            if (period.status == Types.PeriodStatus.PayoutOpen) {
                if (period.payoutDeadline == 0 || block.timestamp < period.payoutDeadline) {
                    break;
                }

                _finalizePayoutAndAdvance(period);
                if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) {
                    break;
                }
                continue;
            }

            break;
        }
    }

    function _advanceCollectingToAuction(PeriodState storage period) internal {
        if (period.status != Types.PeriodStatus.Collecting) revert Errors.InvalidState();
        if (block.timestamp < period.contributionDeadline) revert Errors.DeadlineNotReached();
        if (!_allActiveContributed(period)) revert Errors.ContributionMissing();

        period.status = Types.PeriodStatus.Auction;
        period.auctionDeadline = uint64(block.timestamp) + uint64(_auctionWindow);
    }

    function _selectRecipientAndOpenPayout(PeriodState storage period) internal {
        if (period.status != Types.PeriodStatus.Auction) revert Errors.AuctionNotOpen();
        if (period.auctionDeadline == 0 || block.timestamp < period.auctionDeadline) {
            revert Errors.DeadlineNotReached();
        }
        if (period.recipient != address(0)) revert Errors.AuctionAlreadyClosed();

        address recipient;
        uint256 discount;

        if (period.bestBidder != address(0)) {
            recipient = period.bestBidder;
            discount = period.bestDiscount;
        } else {
            address[] memory eligible = _eligibleRecipients();
            if (eligible.length == 0) revert Errors.NoEligibleRecipient();

            address reputation = _reputationAdapter();
            bytes32 snapshotId = period.reputationSnapshotId;

            if (snapshotId == bytes32(0) && reputation != address(0)) {
                snapshotId = IChainoraReputationAdapter(reputation)
                    .snapshotPeriodScores(_poolId, _currentCycle, _currentPeriod, eligible);
                period.reputationSnapshotId = snapshotId;
            }

            recipient = eligible[0];
            if (snapshotId != bytes32(0) && reputation != address(0)) {
                uint256 bestScore = IChainoraReputationAdapter(reputation).scoreOfAt(snapshotId, recipient);
                uint256 len = eligible.length;
                for (uint256 i = 1; i < len; i++) {
                    uint256 score = IChainoraReputationAdapter(reputation).scoreOfAt(snapshotId, eligible[i]);
                    if (score > bestScore) {
                        bestScore = score;
                        recipient = eligible[i];
                    }
                }
            }
        }

        if (discount >= period.totalContributed) revert Errors.InvalidConfig();

        period.recipient = recipient;
        period.payoutAmount = period.totalContributed - discount;
        period.status = Types.PeriodStatus.PayoutOpen;
        period.payoutDeadline = uint64(block.timestamp) + uint64(_payoutWindow());
        _hasReceivedInCycle[_currentCycle][recipient] = true;

        if (discount > 0 && _activeMemberCount > 1) {
            uint256 share = discount / (_activeMemberCount - 1);
            if (share > 0) {
                uint256 len = _members.length;
                for (uint256 i = 0; i < len; i++) {
                    address member = _members[i];
                    if (_isActiveMember[member] && member != recipient) {
                        _claimableYield[member] += share;
                        emit ChainoraYieldAccrued(_currentCycle, _currentPeriod, member, share);
                    }
                }
            }
        }

        emit ChainoraRecipientSelected(_currentCycle, _currentPeriod, recipient, period.payoutAmount, discount);
    }

    function _finalizePayoutAndAdvance(PeriodState storage period) internal {
        if (period.status != Types.PeriodStatus.PayoutOpen) revert Errors.InvalidState();
        if (period.payoutDeadline == 0 || block.timestamp < period.payoutDeadline) revert Errors.DeadlineNotReached();

        period.status = Types.PeriodStatus.Finalized;
        // Lock the period before transferring so a malicious token cannot reenter finalization.
        if (!period.payoutClaimed) {
            _payoutRecipient(period, period.recipient);
        }

        emit ChainoraPeriodFinalized(_currentCycle, _currentPeriod);
        _completeCycleOrOpenNextPeriod();
    }

    function _completeCycleOrOpenNextPeriod() internal {
        if (_allActiveMembersReceivedInCurrentCycle()) {
            _cycleCompleted = true;
            _extendVoteOpen = true;
            _extendVoteDeadline = uint64(block.timestamp) + uint64(EXTEND_VOTE_DURATION);
            _extendVoteRound += 1;
            _extendYesVotes = 0;
        } else {
            _currentPeriod += 1;
            _openPeriod(_currentCycle, _currentPeriod);
        }
    }

    function _runtimeStatus() internal view returns (Types.RuntimeStatusView memory status) {
        status.poolStatus = _poolStatus;
        status.currentCycle = _currentCycle;
        status.currentPeriod = _currentPeriod;
        status.cycleCompleted = _cycleCompleted;
        status.extendVoteOpen = _extendVoteOpen;
        status.extendVoteDeadline = _extendVoteDeadline;
        status.extendVoteExpired = _extendVoteOpen && _extendVoteDeadline != 0 && block.timestamp > _extendVoteDeadline;
        status.unpaidActiveMembers = new address[](0);

        if (_currentCycle == 0 || _currentPeriod == 0) {
            return status;
        }

        PeriodState storage period = _periods[_currentCycle][_currentPeriod];
        status.storedPeriodStatus = period.status;
        status.startAt = period.startAt;
        status.contributionDeadline = period.contributionDeadline;
        status.auctionDeadline = period.auctionDeadline;
        status.payoutDeadline = period.payoutDeadline;

        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) {
            return status;
        }

        if (period.status == Types.PeriodStatus.Collecting) {
            bool allContributed = _allActiveContributed(period);
            status.allActiveContributed = allContributed;
            if (period.contributionDeadline != 0 && block.timestamp >= period.contributionDeadline) {
                status.auctionReady = allContributed;
                status.defaultPending = !allContributed;
            }
            status.unpaidActiveMembers = _unpaidActiveMembers(period);
            return status;
        }

        status.allActiveContributed = _allActiveContributed(period);

        if (period.status == Types.PeriodStatus.Auction) {
            status.auctionCloseReady = period.auctionDeadline != 0 && block.timestamp >= period.auctionDeadline;
        } else if (period.status == Types.PeriodStatus.PayoutOpen) {
            status.finalizeReady = period.payoutDeadline != 0 && block.timestamp >= period.payoutDeadline;
        }
    }

    function _payoutRecipient(PeriodState storage period, address recipient) internal {
        period.payoutClaimed = true;
        _stablecoin.safeTransfer(recipient, period.payoutAmount);

        emit ChainoraPayoutClaimed(_currentCycle, _currentPeriod, recipient, period.payoutAmount);
    }

    function _eligibleRecipients() private view returns (address[] memory recipients) {
        recipients = new address[](_activeMemberCount);
        uint256 cursor;
        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member] && !_hasReceivedInCycle[_currentCycle][member]) {
                recipients[cursor] = member;
                cursor += 1;
            }
        }

        assembly {
            mstore(recipients, cursor)
        }
    }

    function _unpaidActiveMembers(PeriodState storage period) private view returns (address[] memory unpaid) {
        unpaid = new address[](_activeMemberCount);
        uint256 cursor;
        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member] && !period.contributed[member]) {
                unpaid[cursor] = member;
                cursor += 1;
            }
        }

        assembly {
            mstore(unpaid, cursor)
        }
    }
}
