// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
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
        pool.syncRuntime();

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.archive();
    }

    function testOnlyActiveMemberCanSyncRuntime() external {
        (uint64 payoutDeadline,) = _reachPayoutOpenWithBid(false);

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.syncRuntime();

        vm.warp(uint256(payoutDeadline) + 1);

        vm.prank(member1);
        pool.syncRuntime();

        assertEq(pool.currentPeriod(), 2);
    }

    function testSyncRuntimeDoesNotFinalizeBeforePayoutDeadline() external {
        _reachPayoutOpenWithBid(false);

        vm.prank(member1);
        pool.syncRuntime();

        assertEq(pool.currentPeriod(), 1);
        assertFalse(pool.cycleCompleted());
    }

    function testFinalizeAutoPaysUnclaimedRecipientAfterPeriodEnd() external {
        (uint64 payoutDeadline, uint256 payoutAmount) = _reachPayoutOpenWithBid(false);
        uint256 balanceBefore = token.balanceOf(member1);

        vm.warp(uint256(payoutDeadline) + 1);

        vm.prank(member2);
        pool.syncRuntime();

        assertEq(token.balanceOf(member1), balanceBefore + payoutAmount);
        assertEq(pool.currentPeriod(), 2);

        (,,,,,,,,, bool payoutClaimed,) = pool.periodInfo(1, 1);
        assertTrue(payoutClaimed);
    }

    function testFinalizeAfterManualClaimDoesNotDoublePay() external {
        (uint64 payoutDeadline,) = _reachPayoutOpenWithBid(true);
        uint256 balanceAfterClaim = token.balanceOf(member1);

        vm.warp(uint256(payoutDeadline) + 1);

        vm.prank(member2);
        pool.syncRuntime();

        assertEq(token.balanceOf(member1), balanceAfterClaim);
    }

    function testClaimPayoutFailsAfterAutoFinalizePayout() external {
        (uint64 payoutDeadline,) = _reachPayoutOpenWithBid(false);

        vm.warp(uint256(payoutDeadline) + 1);

        vm.prank(member2);
        pool.syncRuntime();

        vm.prank(member1);
        vm.expectRevert(Errors.PayoutUnavailable.selector);
        pool.claimPayout();
    }

    function _reachPayoutOpenWithBid(bool claimWinnerPayout)
        internal
        returns (uint64 payoutDeadline, uint256 payoutAmount)
    {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        payoutDeadline = status.payoutDeadline;
        (,,,,,,,, payoutAmount,,) = pool.periodInfo(1, 1);

        if (claimWinnerPayout) {
            vm.prank(member1);
            pool.claimPayout();
        }
    }
}
