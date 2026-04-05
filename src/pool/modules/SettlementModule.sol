// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";

abstract contract SettlementModule is PoolStorage {
    using SafeTransferLibExt for address;

    function _claimPayout(address recipient) internal {
        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.PayoutOpen) revert Errors.PayoutUnavailable();
        if (period.recipient != recipient) revert Errors.NotRecipient();
        if (period.payoutClaimed) revert Errors.AlreadyClaimed();

        period.payoutClaimed = true;
        _stablecoin.safeTransfer(recipient, period.payoutAmount);

        emit ChainoraPayoutClaimed(_currentCycle, _currentPeriod, recipient, period.payoutAmount);
    }

    function _claimYield(address member) internal {
        _requireMember(member);
        uint256 amount = _claimableYield[member];
        if (amount == 0) revert Errors.PayoutUnavailable();

        _claimableYield[member] = 0;
        _stablecoin.safeTransfer(member, amount);

        emit ChainoraYieldClaimed(_currentCycle, _currentPeriod, member, amount);
    }

    function _finalizePeriod(address caller) internal {
        _requireActiveMember(caller);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();

        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.PayoutOpen) revert Errors.InvalidState();
        if (!period.payoutClaimed) revert Errors.PayoutUnavailable();

        period.status = Types.PeriodStatus.Finalized;
        emit ChainoraPeriodFinalized(_currentCycle, _currentPeriod);

        if (_allActiveMembersReceivedInCurrentCycle()) {
            _cycleCompleted = true;
            _extendVoteOpen = true;
            _extendVoteRound += 1;
            _extendYesVotes = 0;
        } else {
            _currentPeriod += 1;
            _openPeriod(_currentCycle, _currentPeriod);
        }
    }
}
