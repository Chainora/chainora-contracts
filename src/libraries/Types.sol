// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Types {
    enum PoolStatus {
        Forming,
        Active,
        Paused,
        Archived
    }

    enum PeriodStatus {
        Collecting,
        Auction,
        PayoutOpen,
        Finalized
    }

    struct PoolConfig {
        uint256 contributionAmount;
        uint16 targetMembers;
        uint32 periodDuration;
        uint32 contributionWindow;
        uint32 auctionWindow;
        uint8 maxCycles;
    }

    struct PoolInitConfig {
        uint256 poolId;
        address creator;
        address registry;
        address stablecoin;
        PoolConfig config;
    }
}
