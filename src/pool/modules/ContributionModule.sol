// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {SafeTransferLibExt} from "src/libraries/SafeTransferLibExt.sol";
import {Types} from "src/libraries/Types.sol";
import {RuntimeSyncModule} from "src/pool/modules/RuntimeSyncModule.sol";

abstract contract ContributionModule is RuntimeSyncModule {
    using SafeTransferLibExt for address;

    function _contribute(address member) internal {
        _requireActiveMember(member);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();

        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.Collecting) revert Errors.InvalidState();
        if (block.timestamp > period.contributionDeadline) revert Errors.DeadlinePassed();
        if (period.contributed[member]) revert Errors.AlreadyContributed();

        _stablecoin.safeTransferFrom(member, address(this), _contributionAmount);
        period.contributed[member] = true;
        period.totalContributed += _contributionAmount;

        emit ChainoraContributionPaid(_currentCycle, _currentPeriod, member, _contributionAmount);
    }
}
