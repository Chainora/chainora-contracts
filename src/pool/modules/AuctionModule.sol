// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

abstract contract AuctionModule is PoolStorage {
    function _submitDiscountBid(address bidder, uint256 discount) internal {
        _requireActiveMember(bidder);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();
        if (_hasReceivedInCycle[_currentCycle][bidder]) revert Errors.InvalidState();

        PeriodState storage period = _currentPeriodStorage();
        _ensureAuctionOpen(period);

        if (block.timestamp >= period.auctionDeadline) revert Errors.DeadlinePassed();
        if (discount <= period.bestDiscount) revert Errors.InvalidConfig();

        period.bestBidder = bidder;
        period.bestDiscount = discount;

        emit ChainoraBidSubmitted(_currentCycle, _currentPeriod, bidder, discount);
    }

    function _closeAuctionAndSelectRecipient(address caller) internal {
        _requireActiveMember(caller);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();

        PeriodState storage period = _currentPeriodStorage();
        _ensureAuctionOpen(period);

        if (block.timestamp < period.auctionDeadline) revert Errors.DeadlineNotReached();
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
        _hasReceivedInCycle[_currentCycle][recipient] = true;

        if (discount > 0 && _activeMemberCount > 1) {
            uint256 share = discount / (_activeMemberCount - 1);
            uint256 len = _members.length;
            for (uint256 i = 0; i < len; i++) {
                address member = _members[i];
                if (_isActiveMember[member] && member != recipient) {
                    _claimableYield[member] += share;
                }
            }
        }

        emit ChainoraRecipientSelected(_currentCycle, _currentPeriod, recipient, period.payoutAmount, discount);
    }

    function _ensureAuctionOpen(PeriodState storage period) private {
        if (period.status == Types.PeriodStatus.Collecting) {
            if (block.timestamp < period.contributionDeadline) revert Errors.DeadlineNotReached();
            if (!_allActiveContributed(period)) revert Errors.ContributionMissing();
            period.status = Types.PeriodStatus.Auction;
        } else if (period.status != Types.PeriodStatus.Auction) {
            revert Errors.AuctionNotOpen();
        }
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
}
