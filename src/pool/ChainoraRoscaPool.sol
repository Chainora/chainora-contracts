// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {IChainoraRoscaPool} from "src/pool/IChainoraRoscaPool.sol";
import {MembershipModule} from "src/pool/modules/MembershipModule.sol";
import {ContributionModule} from "src/pool/modules/ContributionModule.sol";
import {AuctionModule} from "src/pool/modules/AuctionModule.sol";
import {SettlementModule} from "src/pool/modules/SettlementModule.sol";
import {DefaultArchiveModule} from "src/pool/modules/DefaultArchiveModule.sol";
import {ExtensionModule} from "src/pool/modules/ExtensionModule.sol";

contract ChainoraRoscaPool is
    IChainoraRoscaPool,
    MembershipModule,
    ContributionModule,
    AuctionModule,
    SettlementModule,
    DefaultArchiveModule,
    ExtensionModule
{
    function initialize(Types.PoolInitConfig calldata initConfig) external {
        if (_initialized) revert Errors.AlreadyInitialized();
        if (
            initConfig.creator == address(0) || initConfig.registry == address(0) || initConfig.stablecoin == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        Types.PoolConfig memory cfg = initConfig.config;
        if (cfg.contributionAmount == 0 || cfg.targetMembers < 2) {
            revert Errors.InvalidConfig();
        }
        if (cfg.targetMembers > type(uint8).max) revert Errors.InvalidConfig();
        if (cfg.periodDuration == 0 || cfg.contributionWindow == 0 || cfg.auctionWindow == 0) {
            revert Errors.InvalidConfig();
        }
        if (cfg.contributionWindow + cfg.auctionWindow >= cfg.periodDuration) {
            revert Errors.InvalidConfig();
        }
        if (initConfig.creatorReputationSnapshot < cfg.minReputation) revert Errors.InsufficientReputation();

        _initialized = true;
        _factory = msg.sender;

        _poolId = initConfig.poolId;
        _registry = initConfig.registry;
        _stablecoin = initConfig.stablecoin;
        _creator = initConfig.creator;
        _publicRecruitment = initConfig.publicRecruitment;

        _contributionAmount = cfg.contributionAmount;
        _minReputation = cfg.minReputation;
        _targetMembers = cfg.targetMembers;
        _periodDuration = cfg.periodDuration;
        _contributionWindow = cfg.contributionWindow;
        _auctionWindow = cfg.auctionWindow;
        _maxCycles = uint8(cfg.targetMembers);

        _poolStatus = Types.PoolStatus.Forming;

        _addMember(initConfig.creator);
        _memberReputationSnapshot[initConfig.creator] = initConfig.creatorReputationSnapshot;
    }

    function proposeInvite(address candidate) external returns (uint256 proposalId) {
        proposalId = _proposeInvite(msg.sender, candidate);
    }

    function voteInvite(uint256 proposalId, bool support) external {
        _voteInvite(msg.sender, proposalId, support);
    }

    function acceptInvite(uint256 proposalId) external {
        _acceptInvite(msg.sender, proposalId);
    }

    function submitJoinRequest() external returns (uint256 requestId) {
        requestId = _submitJoinRequest(msg.sender);
    }

    function voteJoinRequest(uint256 requestId, bool support) external {
        _voteJoinRequest(msg.sender, requestId, support);
    }

    function acceptJoinRequest(uint256 requestId) external {
        _acceptJoinRequest(msg.sender, requestId);
    }

    function cancelJoinRequest(uint256 requestId) external {
        _cancelJoinRequest(msg.sender, requestId);
    }

    function contribute() external {
        _contribute(msg.sender);
    }

    function submitDiscountBid(uint256 discount) external {
        _submitDiscountBid(msg.sender, discount);
    }

    function closeAuctionAndSelectRecipient() external {
        _closeAuctionAndSelectRecipient(msg.sender);
    }

    function claimPayout() external {
        _claimPayout(msg.sender);
    }

    function claimYield() external {
        _claimYield(msg.sender);
    }

    function finalizePeriod() external {
        _finalizePeriod(msg.sender);
    }

    function markDefaultAndArchive(address defaultedMember) external {
        _markDefaultAndArchive(msg.sender, defaultedMember);
    }

    function voteExtendCycle(bool support) external {
        _voteExtendCycle(msg.sender, support);
    }

    function archive() external {
        _archive(msg.sender);
    }

    function claimArchiveRefund() external {
        _claimArchiveRefund(msg.sender);
    }

    function leaveAfterArchive() external {
        _leaveAfterArchive(msg.sender);
    }

    function poolId() external view returns (uint256) {
        return _poolId;
    }

    function factory() external view returns (address) {
        return _factory;
    }

    function registry() external view returns (address) {
        return _registry;
    }

    function stablecoin() external view returns (address) {
        return _stablecoin;
    }

    function creator() external view returns (address) {
        return _creator;
    }

    function poolStatus() external view returns (Types.PoolStatus) {
        return _poolStatus;
    }

    function currentCycle() external view returns (uint256) {
        return _currentCycle;
    }

    function currentPeriod() external view returns (uint256) {
        return _currentPeriod;
    }

    function contributionAmount() external view returns (uint256) {
        return _contributionAmount;
    }

    function publicRecruitment() external view returns (bool) {
        return _publicRecruitment;
    }

    function targetMembers() external view returns (uint16) {
        return _targetMembers;
    }

    function minReputation() external view returns (uint256) {
        return _minReputation;
    }

    function periodDuration() external view returns (uint32) {
        return _periodDuration;
    }

    function contributionWindow() external view returns (uint32) {
        return _contributionWindow;
    }

    function auctionWindow() external view returns (uint32) {
        return _auctionWindow;
    }

    function maxCycles() external view returns (uint8) {
        return _maxCycles;
    }

    function activeMemberCount() external view returns (uint256) {
        return _activeMemberCount;
    }

    function members() external view returns (address[] memory) {
        return _members;
    }

    function isMember(address account) external view returns (bool) {
        return _isMember[account];
    }

    function isActiveMember(address account) external view returns (bool) {
        return _isActiveMember[account];
    }

    function memberReputationSnapshot(address account) external view returns (uint256) {
        return _memberReputationSnapshot[account];
    }

    function inviteProposal(uint256 proposalId)
        external
        view
        returns (address candidate, uint256 yesVotes, uint256 noVotes, bool open)
    {
        InviteProposal storage proposal = _inviteProposals[proposalId];
        candidate = proposal.candidate;
        yesVotes = proposal.yesVotes;
        noVotes = proposal.noVotes;
        open = proposal.open;
    }

    function joinRequest(uint256 requestId)
        external
        view
        returns (address applicant, uint256 yesVotes, uint256 noVotes, bool open)
    {
        JoinRequest storage request = _joinRequests[requestId];
        applicant = request.applicant;
        yesVotes = request.yesVotes;
        noVotes = request.noVotes;
        open = request.open;
    }

    function periodInfo(uint256 cycleId, uint256 periodId)
        external
        view
        returns (
            Types.PeriodStatus status,
            uint64 startAt,
            uint64 contributionDeadline,
            uint64 auctionDeadline,
            address recipient,
            address bestBidder,
            uint256 bestDiscount,
            uint256 totalContributed,
            uint256 payoutAmount,
            bool payoutClaimed,
            bytes32 reputationSnapshotId
        )
    {
        PeriodState storage period = _periods[cycleId][periodId];
        status = period.status;
        startAt = period.startAt;
        contributionDeadline = period.contributionDeadline;
        auctionDeadline = period.auctionDeadline;
        recipient = period.recipient;
        bestBidder = period.bestBidder;
        bestDiscount = period.bestDiscount;
        totalContributed = period.totalContributed;
        payoutAmount = period.payoutAmount;
        payoutClaimed = period.payoutClaimed;
        reputationSnapshotId = period.reputationSnapshotId;
    }

    function hasContributed(uint256 cycleId, uint256 periodId, address member) external view returns (bool) {
        return _periods[cycleId][periodId].contributed[member];
    }

    function hasReceivedInCycle(uint256 cycleId, address member) external view returns (bool) {
        return _hasReceivedInCycle[cycleId][member];
    }

    function claimableYield(address member) external view returns (uint256) {
        return _claimableYield[member];
    }

    function claimableArchiveRefund(address member) external view returns (uint256) {
        return _claimableArchiveRefund[member];
    }

    function cycleCompleted() external view returns (bool) {
        return _cycleCompleted;
    }

    function extendVoteState() external view returns (bool open, uint256 round, uint256 yesVotes) {
        open = _extendVoteOpen;
        round = _extendVoteRound;
        yesVotes = _extendYesVotes;
    }

    function hasLeftArchive(address member) external view returns (bool) {
        return _leftArchive[member];
    }
}
