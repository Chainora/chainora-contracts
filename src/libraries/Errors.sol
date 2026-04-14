// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Errors {
    error ZeroAddress();
    error InvalidConfig();
    error Unauthorized();
    error InvalidState();
    error AlreadyInitialized();
    error AlreadyVoted();
    error ProposalClosed();
    error ProposalNotPassed();
    error NotInvitee();
    error NotApplicant();
    error NotMember();
    error NotActiveMember();
    error RequestAlreadyOpen();
    error DeadlineNotReached();
    error DeadlinePassed();
    error AlreadyContributed();
    error ContributionMissing();
    error AuctionNotOpen();
    error AuctionAlreadyClosed();
    error NoEligibleRecipient();
    error NotRecipient();
    error PayoutUnavailable();
    error AlreadyClaimed();
    error PoolNotArchived();
    error AlreadyLeft();
    error AlreadyVerified();
    error AttestationExpired();
    error AttestationUserMismatch();
    error InvalidAttestationNonce();
    error InvalidAttestationSignature();
    error UntrustedVerifier();
    error UpgradeImplementationInvalid();
    error CloneCreateFailed();
}
