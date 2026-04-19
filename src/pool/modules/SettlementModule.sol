// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {Types} from "src/libraries/Types.sol";
import {RuntimeSyncModule} from "src/pool/modules/RuntimeSyncModule.sol";

abstract contract SettlementModule is RuntimeSyncModule {
    using SafeTransferLibExt for address;

    function _claimPayout(address recipient) internal {
        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.PayoutOpen) revert Errors.PayoutUnavailable();
        if (period.recipient != recipient) revert Errors.NotRecipient();
        if (period.payoutClaimed) revert Errors.AlreadyClaimed();

        _payoutRecipient(period, recipient);
    }

    function _claimYield(address member) internal {
        _requireMember(member);
        if (_poolStatus != Types.PoolStatus.Archived) revert Errors.PoolNotArchived();

        uint256 amount = _claimableYield[member];
        if (amount == 0) revert Errors.PayoutUnavailable();

        _claimableYield[member] = 0;
        _stablecoin.safeTransfer(member, amount);

        emit ChainoraYieldClaimed(_currentCycle, _currentPeriod, member, amount);
    }
}
