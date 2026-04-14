// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {PoolStorage} from "src/pool/modules/PoolStorage.sol";

abstract contract DefaultArchiveModule is PoolStorage {
    function _markDefaultAndArchive(address caller, address defaultedMember) internal {
        _requireActiveMember(caller);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();
        if (!_isActiveMember[defaultedMember]) revert Errors.InvalidConfig();

        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.Collecting) revert Errors.InvalidState();
        if (block.timestamp < period.contributionDeadline) revert Errors.DeadlineNotReached();
        if (period.contributed[defaultedMember]) revert Errors.InvalidState();

        uint256 len = _members.length;
        for (uint256 i = 0; i < len; i++) {
            address member = _members[i];
            if (_isActiveMember[member] && period.contributed[member]) {
                _claimableArchiveRefund[member] += _contributionAmount;
            }
        }

        _poolStatus = Types.PoolStatus.Archived;
        emit ChainoraPoolArchivedOnDefault(defaultedMember, _currentCycle, _currentPeriod);
        emit ChainoraPoolArchived();
    }
}
