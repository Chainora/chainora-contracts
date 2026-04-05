// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library PeriodMath {
    function contributionDeadline(uint64 startAt, uint32 contributionWindow) internal pure returns (uint64) {
        return startAt + contributionWindow;
    }

    function auctionDeadline(uint64 startAt, uint32 contributionWindow, uint32 auctionWindow)
        internal
        pure
        returns (uint64)
    {
        return startAt + contributionWindow + auctionWindow;
    }

    function periodEnd(uint64 startAt, uint32 periodDuration) internal pure returns (uint64) {
        return startAt + periodDuration;
    }
}
