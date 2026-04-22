// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolRuntimeSyncTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testRuntimeStatusUsesCanonicalDeadlinesAndSyncAction() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        uint64 expectedAuctionDeadline =
            status.startAt + uint64(pool.contributionWindow()) + uint64(pool.auctionWindow());
        uint64 expectedPayoutDeadline = status.startAt + uint64(pool.periodDuration());

        assertEq(status.auctionDeadline, expectedAuctionDeadline);
        assertEq(status.payoutDeadline, expectedPayoutDeadline);
        assertTrue(status.allActiveContributed);
        _assertSyncAction(status, Types.RuntimeSyncAction.None);
        assertEq(status.projectedRecipient, creator);
        assertEq(status.projectedDiscount, 0);
        assertEq(status.projectedPayoutAmount, CONTRIBUTION * 3);

        vm.warp(uint256(status.contributionDeadline) + 1);

        status = _currentRuntimeStatus();
        _assertSyncAction(status, Types.RuntimeSyncAction.AuctionReady);
        assertEq(status.projectedRecipient, creator);

        vm.prank(creator);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Auction));
        assertEq(status.auctionDeadline, expectedAuctionDeadline);
        assertEq(status.payoutDeadline, expectedPayoutDeadline);
        _assertSyncAction(status, Types.RuntimeSyncAction.None);

        vm.warp(uint256(status.auctionDeadline) + 1);

        status = _currentRuntimeStatus();
        _assertSyncAction(status, Types.RuntimeSyncAction.PayoutReady);

        vm.prank(member1);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.PayoutOpen));
        assertEq(status.payoutDeadline, expectedPayoutDeadline);
        _assertSyncAction(status, Types.RuntimeSyncAction.None);
    }

    function testSubmitDiscountBidAutoSyncsIntoAuction() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        uint64 expectedAuctionDeadline =
            status.startAt + uint64(pool.contributionWindow()) + uint64(pool.auctionWindow());

        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Auction));
        assertEq(status.auctionDeadline, expectedAuctionDeadline);
        assertEq(status.projectedRecipient, member1);
        assertEq(status.projectedDiscount, 10e6);
        assertEq(status.projectedPayoutAmount, (CONTRIBUTION * 3) - 10e6);

        (,,,,, address bestBidder, uint256 bestDiscount,,,,) = pool.periodInfo(1, 1);
        assertEq(bestBidder, member1);
        assertEq(bestDiscount, 10e6);
    }

    function testClaimPayoutAutoSyncsIntoPayoutOpen() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(member1);
        pool.claimPayout();

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.PayoutOpen));
        assertEq(status.projectedRecipient, member1);
        assertEq(status.projectedDiscount, 10e6);
        assertEq(status.projectedPayoutAmount, (CONTRIBUTION * 3) - 10e6);

        (,,,, address recipient,,,,, bool payoutClaimed,) = pool.periodInfo(1, 1);
        assertEq(recipient, member1);
        assertTrue(payoutClaimed);
    }

    function testSyncRuntimeSkipsExpiredAuctionAndOpensPayout() external {
        _contributeAllActive();
        reputationAdapter.setScore(member2, 2000);

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        uint64 expectedPayoutDeadline = status.startAt + uint64(pool.periodDuration());
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(member1);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.PayoutOpen));
        assertEq(status.payoutDeadline, expectedPayoutDeadline);
        assertEq(status.projectedRecipient, member2);
        assertEq(status.projectedDiscount, 0);
        assertEq(status.projectedPayoutAmount, CONTRIBUTION * 3);

        (Types.PeriodStatus periodStatus,,,, address recipient,,,,, bool payoutClaimed,) = pool.periodInfo(1, 1);
        assertEq(uint256(periodStatus), uint256(Types.PeriodStatus.PayoutOpen));
        assertEq(recipient, member2);
        assertFalse(payoutClaimed);
    }

    function testRuntimeStatusProjectsFallbackRecipientFromLiveReputation() external {
        _contributeAllActive();
        reputationAdapter.setScore(member2, 2000);

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Collecting));
        _assertSyncAction(status, Types.RuntimeSyncAction.None);
        assertEq(status.projectedRecipient, member2);
        assertEq(status.projectedDiscount, 0);
        assertEq(status.projectedPayoutAmount, CONTRIBUTION * 3);
    }

    function testRuntimeStatusUsesBidWinnerProjectionBeforePayoutOpens() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        _assertSyncAction(status, Types.RuntimeSyncAction.None);
        assertEq(status.projectedRecipient, member1);
        assertEq(status.projectedDiscount, 10e6);
        assertEq(status.projectedPayoutAmount, (CONTRIBUTION * 3) - 10e6);
    }

    function testRuntimeStatusReportsArchiveReadyAndZeroProjectionWhenContributionMissing() external {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        _assertSyncAction(status, Types.RuntimeSyncAction.None);
        assertEq(status.projectedRecipient, address(0));
        assertEq(status.projectedDiscount, 0);
        assertEq(status.projectedPayoutAmount, 0);

        vm.warp(uint256(status.contributionDeadline) + 1);

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Collecting));
        _assertSyncAction(status, Types.RuntimeSyncAction.ArchiveReady);
        assertEq(status.unpaidActiveMembers.length, 1);
        assertEq(status.unpaidActiveMembers[0], member2);
        assertEq(status.projectedRecipient, address(0));
        assertEq(status.projectedDiscount, 0);
        assertEq(status.projectedPayoutAmount, 0);
    }

    function testSyncRuntimeCanCatchUpFromCollectingPastPeriodEnd() external {
        _contributeAllActive();
        reputationAdapter.setScore(member2, 2000);

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.payoutDeadline) + 1);

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Collecting));
        _assertSyncAction(status, Types.RuntimeSyncAction.FinalizeReady);
        assertEq(status.projectedRecipient, member2);
        assertEq(status.projectedPayoutAmount, CONTRIBUTION * 3);

        vm.prank(member1);
        pool.syncRuntime();

        assertEq(pool.currentPeriod(), 2);

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Collecting));
        _assertSyncAction(status, Types.RuntimeSyncAction.None);

        (Types.PeriodStatus periodStatus,,,, address recipient,,,, uint256 payoutAmount, bool payoutClaimed,) =
            pool.periodInfo(1, 1);
        assertEq(uint256(periodStatus), uint256(Types.PeriodStatus.Finalized));
        assertEq(recipient, member2);
        assertEq(payoutAmount, CONTRIBUTION * 3);
        assertTrue(payoutClaimed);
    }

    function testContributeAutoFinalizesExpiredPayoutAndOpensNextPeriod() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();

        vm.prank(member1);
        pool.claimPayout();

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.payoutDeadline) + 1);

        vm.prank(creator);
        pool.contribute();

        assertEq(pool.currentPeriod(), 2);
        assertTrue(pool.hasContributed(1, 2, creator));

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Collecting));
        assertEq(
            status.auctionDeadline, status.startAt + uint64(pool.contributionWindow()) + uint64(pool.auctionWindow())
        );
        assertEq(status.payoutDeadline, status.startAt + uint64(pool.periodDuration()));
        _assertSyncAction(status, Types.RuntimeSyncAction.None);
        assertEq(status.projectedRecipient, address(0));
        assertEq(status.projectedPayoutAmount, 0);
    }

    function testExtendVoteDeadlineStillNeedsManualArchive() external {
        _finishPeriodWithFallback(member1, 1000);
        _finishPeriodWithFallback(member2, 2000);
        _finishPeriodWithFallback(creator, 3000);

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        assertTrue(status.extendVoteOpen);

        vm.warp(uint256(status.extendVoteDeadline) + 1);

        status = _currentRuntimeStatus();
        assertTrue(status.extendVoteOpen);
        assertGt(block.timestamp, status.extendVoteDeadline);

        vm.prank(creator);
        vm.expectRevert(Errors.DeadlinePassed.selector);
        pool.voteExtendCycle(true);

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Active));

        vm.prank(creator);
        pool.archive();

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Archived));
    }

    function _finishPeriodWithFallback(address expectedRecipient, uint256 recipientScore) internal {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        reputationAdapter.setScore(expectedRecipient, recipientScore);

        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(member1);
        pool.syncRuntime();

        vm.prank(expectedRecipient);
        pool.claimPayout();

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.payoutDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();
    }

    function _assertSyncAction(Types.RuntimeStatusView memory status, Types.RuntimeSyncAction expected) internal pure {
        assertEq(uint256(status.syncAction), uint256(expected));
    }
}
