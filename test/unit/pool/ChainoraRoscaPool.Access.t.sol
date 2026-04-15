// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolAccessTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testNonMemberCannotCallTransitions() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.contribute();

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.closeAuctionAndSelectRecipient();

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.archive();
    }

    function testOnlyActiveMemberCanFinalize() external {
        (uint64 startAt,) = _reachPayoutOpenWithBid(false);

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.finalizePeriod();

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member1);
        pool.finalizePeriod();

        assertEq(pool.currentPeriod(), 2);
    }

    function testFinalizeRevertsBeforePeriodEnd() external {
        _reachPayoutOpenWithBid(false);

        vm.prank(member1);
        vm.expectRevert(Errors.DeadlineNotReached.selector);
        pool.finalizePeriod();
    }

    function testFinalizeAutoPaysUnclaimedRecipientAfterPeriodEnd() external {
        (uint64 startAt, uint256 payoutAmount) = _reachPayoutOpenWithBid(false);
        uint256 balanceBefore = token.balanceOf(member1);

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member2);
        pool.finalizePeriod();

        assertEq(token.balanceOf(member1), balanceBefore + payoutAmount);
        assertEq(pool.currentPeriod(), 2);

        (,,,,,,,,, bool payoutClaimed,) = pool.periodInfo(1, 1);
        assertTrue(payoutClaimed);
    }

    function testFinalizeAfterManualClaimDoesNotDoublePay() external {
        (uint64 startAt,) = _reachPayoutOpenWithBid(true);
        uint256 balanceAfterClaim = token.balanceOf(member1);

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member2);
        pool.finalizePeriod();

        assertEq(token.balanceOf(member1), balanceAfterClaim);
    }

    function testClaimPayoutFailsAfterAutoFinalizePayout() external {
        (uint64 startAt,) = _reachPayoutOpenWithBid(false);

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member2);
        pool.finalizePeriod();

        vm.prank(member1);
        vm.expectRevert(Errors.PayoutUnavailable.selector);
        pool.claimPayout();
    }

    function _reachPayoutOpenWithBid(bool claimWinnerPayout) internal returns (uint64 startAt, uint256 payoutAmount) {
        _contributeAllActive();

        uint64 contributionDeadline;
        uint64 auctionDeadline;
        (, startAt, contributionDeadline, auctionDeadline,,,,,,,) = pool.periodInfo(1, 1);
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        vm.warp(uint256(auctionDeadline) + 1);

        vm.prank(creator);
        pool.closeAuctionAndSelectRecipient();

        (,,,,,,,, payoutAmount,,) = pool.periodInfo(1, 1);

        if (claimWinnerPayout) {
            vm.prank(member1);
            pool.claimPayout();
        }
    }
}
