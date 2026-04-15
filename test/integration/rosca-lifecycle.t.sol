// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract RoscaLifecycleIntegrationTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testFullLifecycleToArchive() external {
        _finishPeriodWithBid(member1, 10e6);
        _finishPeriodWithFallback(member2, 1000);
        _finishPeriodWithFallback(creator, 2000);

        assertTrue(pool.cycleCompleted());

        vm.prank(creator);
        pool.voteExtendCycle(true);
        vm.prank(member1);
        pool.voteExtendCycle(true);
        vm.prank(member2);
        pool.voteExtendCycle(false);

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Archived));
    }

    function testFinalizeAutoPaysBidWinnerIfUnclaimed() external {
        _contributeAllActive();

        (, uint64 startAt, uint64 contributionDeadline, uint64 auctionDeadline,,,,,,,) =
            pool.periodInfo(pool.currentCycle(), pool.currentPeriod());

        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        vm.warp(uint256(auctionDeadline) + 1);

        vm.prank(creator);
        pool.closeAuctionAndSelectRecipient();

        (,,,, address recipient,,,, uint256 payoutAmount, bool payoutClaimed,) =
            pool.periodInfo(pool.currentCycle(), pool.currentPeriod());
        assertEq(recipient, member1);
        assertFalse(payoutClaimed);

        uint256 balanceBefore = token.balanceOf(recipient);

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member2);
        pool.finalizePeriod();

        assertEq(token.balanceOf(recipient), balanceBefore + payoutAmount);
        assertEq(pool.currentPeriod(), 2);
    }

    function _finishPeriodWithBid(address bidder, uint256 discount) internal {
        _contributeAllActive();

        (, uint64 startAt, uint64 contributionDeadline, uint64 auctionDeadline,,,,,,,) =
            pool.periodInfo(pool.currentCycle(), pool.currentPeriod());

        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(bidder);
        pool.submitDiscountBid(discount);

        vm.warp(uint256(auctionDeadline) + 1);

        vm.prank(creator);
        pool.closeAuctionAndSelectRecipient();

        vm.prank(bidder);
        pool.claimPayout();

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member1);
        pool.finalizePeriod();
    }

    function _finishPeriodWithFallback(address expectedRecipient, uint256 recipientScore) internal {
        _contributeAllActive();

        (, uint64 startAt, uint64 contributionDeadline, uint64 auctionDeadline,,,,,,,) =
            pool.periodInfo(pool.currentCycle(), pool.currentPeriod());

        reputationAdapter.setScore(expectedRecipient, recipientScore);

        vm.warp(uint256(contributionDeadline) + 1);
        vm.warp(uint256(auctionDeadline) + 1);

        vm.prank(member1);
        pool.closeAuctionAndSelectRecipient();

        (,,,, address recipient,,,,,,) = pool.periodInfo(pool.currentCycle(), pool.currentPeriod());
        assertEq(recipient, expectedRecipient);

        vm.prank(expectedRecipient);
        pool.claimPayout();

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(creator);
        pool.finalizePeriod();
    }
}
