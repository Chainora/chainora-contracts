// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {RuntimeSyncModule} from "src/pool/modules/RuntimeSyncModule.sol";

abstract contract AuctionModule is RuntimeSyncModule {
    function _submitDiscountBid(address bidder, uint256 discount) internal {
        _requireActiveMember(bidder);
        if (_poolStatus != Types.PoolStatus.Active || _cycleCompleted) revert Errors.InvalidState();
        if (_hasReceivedInCycle[_currentCycle][bidder]) revert Errors.InvalidState();

        PeriodState storage period = _currentPeriodStorage();
        if (period.status != Types.PeriodStatus.Auction) revert Errors.AuctionNotOpen();
        if (block.timestamp >= period.auctionDeadline) revert Errors.DeadlinePassed();
        if (discount <= period.bestDiscount) revert Errors.InvalidConfig();

        period.bestBidder = bidder;
        period.bestDiscount = discount;

        emit ChainoraBidSubmitted(_currentCycle, _currentPeriod, bidder, discount);
    }
}
