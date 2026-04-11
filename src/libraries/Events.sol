// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Events {
    event ChainoraPoolCreated(uint256 indexed poolId, address indexed pool, address indexed creator);

    event ChainoraRegistryStablecoinSet(address indexed oldValue, address indexed newValue);
    event ChainoraRegistryDeviceAdapterSet(address indexed oldValue, address indexed newValue);
    event ChainoraRegistryReputationAdapterSet(address indexed oldValue, address indexed newValue);
    event ChainoraRegistryStakingAdapterSet(address indexed oldValue, address indexed newValue);
    event ChainoraDeviceTrustVerifierSet(address indexed verifier, bool allowed);
    event ChainoraDeviceVerified(address indexed user, address indexed verifier, uint256 indexed nonce);
    event ChainoraDeviceVerificationRevoked(address indexed user, uint256 nextNonce);

    event ChainoraUpgraded(address indexed newImplementation);

    event ChainoraInviteProposed(uint256 indexed proposalId, address indexed candidate, address indexed proposer);
    event ChainoraInviteVoted(uint256 indexed proposalId, address indexed voter, bool support);
    event ChainoraInviteAccepted(uint256 indexed proposalId, address indexed member);
    event ChainoraJoinRequestSubmitted(uint256 indexed requestId, address indexed applicant);
    event ChainoraJoinRequestVoted(uint256 indexed requestId, address indexed voter, bool support);
    event ChainoraJoinRequestCanceled(uint256 indexed requestId, address indexed applicant);
    event ChainoraJoinRequestAccepted(uint256 indexed requestId, address indexed applicant);
    event ChainoraPoolActivated(uint256 indexed cycleId, uint64 periodStartAt);

    event ChainoraContributionPaid(
        uint256 indexed cycleId, uint256 indexed periodId, address indexed member, uint256 amount
    );
    event ChainoraBidSubmitted(
        uint256 indexed cycleId, uint256 indexed periodId, address indexed bidder, uint256 discount
    );
    event ChainoraRecipientSelected(
        uint256 indexed cycleId,
        uint256 indexed periodId,
        address indexed recipient,
        uint256 payoutAmount,
        uint256 discount
    );
    event ChainoraPayoutClaimed(
        uint256 indexed cycleId, uint256 indexed periodId, address indexed recipient, uint256 amount
    );
    event ChainoraYieldClaimed(
        uint256 indexed cycleId, uint256 indexed periodId, address indexed member, uint256 amount
    );
    event ChainoraPeriodFinalized(uint256 indexed cycleId, uint256 indexed periodId);

    event ChainoraPoolPaused(address indexed defaultedMember, uint256 indexed cycleId, uint256 indexed periodId);
    event ChainoraContinueVoted(address indexed voter, bool support, uint256 yesVotes, uint256 requiredVotes);
    event ChainoraPoolResumed(uint256 indexed cycleId, uint256 indexed nextPeriodId);

    event ChainoraExtendVoted(address indexed voter, bool support, uint256 yesVotes, uint256 requiredVotes);
    event ChainoraPoolArchived();
    event ChainoraLeftPool(address indexed member);

    event ChainoraTimelockScheduled(bytes32 indexed id, address indexed target, uint256 value, uint64 readyAt);
    event ChainoraTimelockExecuted(bytes32 indexed id, address indexed target, uint256 value, bytes returnData);
    event ChainoraTimelockCanceled(bytes32 indexed id);
    event ChainoraTimelockDelayUpdated(uint64 oldDelay, uint64 newDelay);
}
