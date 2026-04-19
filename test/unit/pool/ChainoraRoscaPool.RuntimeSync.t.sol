// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolRuntimeSyncTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testRuntimeStatusUsesPhaseLocalDeadlines() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        assertEq(status.auctionDeadline, 0);
        assertEq(status.payoutDeadline, 0);

        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Auction));
        assertEq(status.auctionDeadline, uint64(block.timestamp) + uint64(pool.auctionWindow()));
        assertEq(status.payoutDeadline, 0);

        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(member1);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.PayoutOpen));
        assertEq(
            status.payoutDeadline,
            uint64(block.timestamp) + uint64(pool.periodDuration() - pool.contributionWindow() - pool.auctionWindow())
        );
    }

    function testSubmitDiscountBidAutoSyncsIntoAuction() external {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Auction));
        assertEq(status.auctionDeadline, uint64(block.timestamp) + uint64(pool.auctionWindow()));

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

        (,,,, address recipient,,,,, bool payoutClaimed,) = pool.periodInfo(1, 1);
        assertEq(recipient, member1);
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
        assertEq(status.auctionDeadline, 0);
        assertEq(status.payoutDeadline, 0);
    }

    function testRuntimeStatusReportsDefaultPending() external {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        status = _currentRuntimeStatus();
        assertEq(uint256(status.storedPeriodStatus), uint256(Types.PeriodStatus.Collecting));
        assertTrue(status.defaultPending);
        assertFalse(status.auctionReady);
        assertEq(status.unpaidActiveMembers.length, 1);
        assertEq(status.unpaidActiveMembers[0], member2);
    }

    function testExtendVoteExpiresAndStillNeedsManualArchive() external {
        _finishPeriodWithFallback(member1, 1000);
        _finishPeriodWithFallback(member2, 2000);
        _finishPeriodWithFallback(creator, 3000);

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        assertTrue(status.extendVoteOpen);
        assertFalse(status.extendVoteExpired);

        vm.warp(uint256(status.extendVoteDeadline) + 1);

        status = _currentRuntimeStatus();
        assertTrue(status.extendVoteExpired);

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
}
