// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {PeriodMath} from "src/libraries/PeriodMath.sol";
import {Types} from "src/libraries/Types.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

abstract contract RuntimeSyncModule is PoolStorage {
    using SafeTransferLibExt for address;

    uint32 internal constant EXTEND_VOTE_DURATION = 1 days;

    struct RuntimeResolution {
        uint64 contributionDeadline;
        uint64 auctionDeadline;
        uint64 payoutDeadline;
        bool allActiveContributed;
        Types.RuntimeSyncAction syncAction;
    }

    struct ProjectedPayout {
        address recipient;
        uint256 discount;
        uint256 payoutAmount;
    }

    function _syncRuntimePhase(address caller) internal {
        _requireActiveMember(caller);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) return;

        while (true) {
            PeriodState storage period = _currentPeriodStorage();
            RuntimeResolution memory resolution = _resolveRuntime(period);

            if (
                resolution.syncAction == Types.RuntimeSyncAction.None
                    || resolution.syncAction == Types.RuntimeSyncAction.ArchiveReady
            ) {
                break;
            }

            if (resolution.syncAction == Types.RuntimeSyncAction.AuctionReady) {
                _advanceCollectingToAuction(period, resolution.auctionDeadline);
                continue;
            }

            if (resolution.syncAction == Types.RuntimeSyncAction.PayoutReady) {
                if (period.status == Types.PeriodStatus.Collecting) {
                    _skipAuctionAndOpenPayout(period, resolution.auctionDeadline, resolution.payoutDeadline);
                    continue;
                }
                if (period.status == Types.PeriodStatus.Auction) {
                    _selectRecipientAndOpenPayout(period, resolution.payoutDeadline);
                    continue;
                }
                break;
            }

            if (resolution.syncAction == Types.RuntimeSyncAction.FinalizeReady) {
                if (period.status == Types.PeriodStatus.Collecting) {
                    _skipAuctionAndOpenPayout(period, resolution.auctionDeadline, resolution.payoutDeadline);
                    continue;
                }
                if (period.status == Types.PeriodStatus.Auction) {
                    _selectRecipientAndOpenPayout(period, resolution.payoutDeadline);
                    continue;
                }
                if (period.status == Types.PeriodStatus.PayoutOpen) {
                    _finalizePayoutAndAdvance(period, resolution.payoutDeadline);
                    if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) {
                        break;
                    }
                    continue;
                }
            }

            break;
        }
    }

    function _advanceCollectingToAuction(PeriodState storage period, uint64 auctionDeadline) internal {
        if (period.status != Types.PeriodStatus.Collecting) revert Errors.InvalidState();
        uint64 contributionDeadline = _contributionDeadlineOf(period);
        if (block.timestamp < contributionDeadline) revert Errors.DeadlineNotReached();
        if (!_allActiveContributed(period)) revert Errors.ContributionMissing();

        period.status = Types.PeriodStatus.Auction;
        period.auctionDeadline = auctionDeadline;
    }

    function _skipAuctionAndOpenPayout(PeriodState storage period, uint64 auctionDeadline, uint64 payoutDeadline)
        internal
    {
        if (period.status != Types.PeriodStatus.Collecting) revert Errors.InvalidState();
        uint64 contributionDeadline = _contributionDeadlineOf(period);
        if (block.timestamp < contributionDeadline) revert Errors.DeadlineNotReached();
        if (!_allActiveContributed(period)) revert Errors.ContributionMissing();

        period.status = Types.PeriodStatus.Auction;
        period.auctionDeadline = auctionDeadline;

        _openPayout(period, payoutDeadline);
    }

    function _selectRecipientAndOpenPayout(PeriodState storage period, uint64 payoutDeadline) internal {
        if (period.status != Types.PeriodStatus.Auction) revert Errors.AuctionNotOpen();
        uint64 auctionDeadline = _auctionDeadlineOf(period);
        if (auctionDeadline == 0 || block.timestamp < auctionDeadline) {
            revert Errors.DeadlineNotReached();
        }
        if (period.recipient != address(0)) revert Errors.AuctionAlreadyClosed();

        period.auctionDeadline = auctionDeadline;
        _openPayout(period, payoutDeadline);
    }

    function _openPayout(PeriodState storage period, uint64 payoutDeadline) internal {
        if (period.status != Types.PeriodStatus.Auction) revert Errors.AuctionNotOpen();
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

            recipient = snapshotId != bytes32(0) && reputation != address(0)
                ? _highestScoreRecipient(eligible, reputation, snapshotId, true)
                : eligible[0];
        }

        if (discount >= period.totalContributed) revert Errors.InvalidConfig();

        period.recipient = recipient;
        period.payoutAmount = period.totalContributed - discount;
        period.status = Types.PeriodStatus.PayoutOpen;
        period.payoutDeadline = payoutDeadline;
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

    function _finalizePayoutAndAdvance(PeriodState storage period, uint64 payoutDeadline) internal {
        if (period.status != Types.PeriodStatus.PayoutOpen) revert Errors.InvalidState();
        if (payoutDeadline == 0 || block.timestamp < payoutDeadline) revert Errors.DeadlineNotReached();

        period.payoutDeadline = payoutDeadline;
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
        status.unpaidActiveMembers = new address[](0);

        if (_currentCycle == 0 || _currentPeriod == 0) {
            return status;
        }

        PeriodState storage period = _periods[_currentCycle][_currentPeriod];
        RuntimeResolution memory resolution = _resolveRuntime(period);
        ProjectedPayout memory projection = _projectPayout(period, resolution.allActiveContributed);

        status.storedPeriodStatus = period.status;
        status.syncAction = resolution.syncAction;
        status.startAt = period.startAt;
        status.contributionDeadline = resolution.contributionDeadline;
        status.auctionDeadline = resolution.auctionDeadline;
        status.payoutDeadline = resolution.payoutDeadline;
        status.allActiveContributed = resolution.allActiveContributed;
        status.projectedRecipient = projection.recipient;
        status.projectedDiscount = projection.discount;
        status.projectedPayoutAmount = projection.payoutAmount;

        if (period.status == Types.PeriodStatus.Collecting) {
            status.unpaidActiveMembers = _unpaidActiveMembers(period);
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

    function _resolveRuntime(PeriodState storage period) private view returns (RuntimeResolution memory resolution) {
        if (period.startAt == 0) {
            return resolution;
        }

        resolution.contributionDeadline = _contributionDeadlineOf(period);
        resolution.auctionDeadline = _auctionDeadlineOf(period);
        resolution.payoutDeadline = _payoutDeadlineOf(period);
        resolution.allActiveContributed = _allActiveContributed(period);

        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) {
            return resolution;
        }

        if (period.status == Types.PeriodStatus.Collecting) {
            if (block.timestamp < resolution.contributionDeadline) {
                return resolution;
            }

            if (!resolution.allActiveContributed) {
                resolution.syncAction = Types.RuntimeSyncAction.ArchiveReady;
                return resolution;
            }

            if (block.timestamp < resolution.auctionDeadline) {
                resolution.syncAction = Types.RuntimeSyncAction.AuctionReady;
                return resolution;
            }

            if (block.timestamp < resolution.payoutDeadline) {
                resolution.syncAction = Types.RuntimeSyncAction.PayoutReady;
                return resolution;
            }

            resolution.syncAction = Types.RuntimeSyncAction.FinalizeReady;
            return resolution;
        }

        if (period.status == Types.PeriodStatus.Auction) {
            if (block.timestamp >= resolution.payoutDeadline) {
                resolution.syncAction = Types.RuntimeSyncAction.FinalizeReady;
            } else if (block.timestamp >= resolution.auctionDeadline) {
                resolution.syncAction = Types.RuntimeSyncAction.PayoutReady;
            }
            return resolution;
        }

        if (period.status == Types.PeriodStatus.PayoutOpen && block.timestamp >= resolution.payoutDeadline) {
            resolution.syncAction = Types.RuntimeSyncAction.FinalizeReady;
        }
    }

    function _projectPayout(PeriodState storage period, bool allActiveContributed)
        private
        view
        returns (ProjectedPayout memory projection)
    {
        if (period.recipient != address(0)) {
            projection.recipient = period.recipient;
            projection.discount = period.bestBidder == period.recipient ? period.bestDiscount : 0;
            projection.payoutAmount = period.payoutAmount;
            return projection;
        }

        if (!allActiveContributed) {
            return projection;
        }

        if (period.bestBidder != address(0)) {
            projection.recipient = period.bestBidder;
            projection.discount = period.bestDiscount;
            if (period.bestDiscount < period.totalContributed) {
                projection.payoutAmount = period.totalContributed - period.bestDiscount;
            }
            return projection;
        }

        address[] memory eligible = _eligibleRecipients();
        if (eligible.length == 0) {
            return projection;
        }

        address reputation = _reputationAdapter();
        projection.recipient = _highestScoreRecipient(eligible, reputation, bytes32(0), false);
        projection.payoutAmount = period.totalContributed;
    }

    function _highestScoreRecipient(address[] memory eligible, address reputation, bytes32 snapshotId, bool useSnapshot)
        private
        view
        returns (address recipient)
    {
        recipient = eligible[0];
        if (reputation == address(0)) {
            return recipient;
        }

        uint256 bestScore = useSnapshot
            ? IChainoraReputationAdapter(reputation).scoreOfAt(snapshotId, recipient)
            : IChainoraReputationAdapter(reputation).scoreOf(recipient);
        uint256 len = eligible.length;
        for (uint256 i = 1; i < len; i++) {
            uint256 score = useSnapshot
                ? IChainoraReputationAdapter(reputation).scoreOfAt(snapshotId, eligible[i])
                : IChainoraReputationAdapter(reputation).scoreOf(eligible[i]);
            if (score > bestScore) {
                bestScore = score;
                recipient = eligible[i];
            }
        }
    }

    function _contributionDeadlineOf(PeriodState storage period) private view returns (uint64) {
        if (period.startAt == 0) {
            return 0;
        }
        return PeriodMath.contributionDeadline(period.startAt, _contributionWindow);
    }

    function _auctionDeadlineOf(PeriodState storage period) private view returns (uint64) {
        if (period.startAt == 0) {
            return 0;
        }
        return PeriodMath.auctionDeadline(period.startAt, _contributionWindow, _auctionWindow);
    }

    function _payoutDeadlineOf(PeriodState storage period) private view returns (uint64) {
        if (period.startAt == 0) {
            return 0;
        }
        return PeriodMath.periodEnd(period.startAt, _periodDuration);
    }
}
