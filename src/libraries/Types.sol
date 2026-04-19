// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Types {
    enum PoolStatus {
        Forming,
        Active,
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
        uint256 minReputation;
        uint16 targetMembers;
        uint32 periodDuration;
        uint32 contributionWindow;
        uint32 auctionWindow;
    }

    struct PoolInitConfig {
        uint256 poolId;
        address creator;
        address registry;
        address stablecoin;
        bool publicRecruitment;
        uint256 creatorReputationSnapshot;
        PoolConfig config;
    }

    struct PoolDiscoveryView {
        uint256 poolId;
        address pool;
        address creator;
        bool publicRecruitment;
        bool listed;
        PoolStatus poolStatus;
        uint256 activeMemberCount;
        uint16 targetMembers;
        uint256 contributionAmount;
        uint256 minReputation;
    }

    struct RuntimeStatusView {
        PoolStatus poolStatus;
        uint256 currentCycle;
        uint256 currentPeriod;
        PeriodStatus storedPeriodStatus;
        uint64 startAt;
        uint64 contributionDeadline;
        uint64 auctionDeadline;
        uint64 payoutDeadline;
        bool cycleCompleted;
        bool extendVoteOpen;
        uint64 extendVoteDeadline;
        bool allActiveContributed;
        bool defaultPending;
        bool auctionReady;
        bool auctionCloseReady;
        bool finalizeReady;
        bool extendVoteExpired;
        address[] unpaidActiveMembers;
    }
}
