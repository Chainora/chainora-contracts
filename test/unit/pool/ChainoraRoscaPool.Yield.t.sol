// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolYieldTest is ChainoraTestBase {
    event ChainoraYieldAccrued(
        uint256 indexed cycleId, uint256 indexed periodId, address indexed member, uint256 amount
    );

    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testYieldAccruesButRemainsLockedUntilArchive() external {
        (uint64 payoutDeadline, uint256 share) = _reachPayoutOpenWithBid(member1, 10e6, true);

        assertEq(pool.claimableYield(creator), share);
        assertEq(pool.claimableYield(member2), share);

        vm.prank(creator);
        vm.expectRevert(Errors.PoolNotArchived.selector);
        pool.claimYield();

        vm.prank(member1);
        pool.claimPayout();

        vm.warp(uint256(payoutDeadline) + 1);

        vm.prank(member2);
        pool.syncRuntime();

        vm.prank(creator);
        vm.expectRevert(Errors.PoolNotArchived.selector);
        pool.claimYield();
    }

    function testArchivedPoolClaimsAggregateYieldFromMultiplePeriods() external {
        _finishBidPeriod(member1, 10e6);
        _finishBidPeriod(member2, 20e6);
        _finishBidPeriod(creator, 30e6);

        assertTrue(pool.cycleCompleted());
        assertEq(pool.claimableYield(creator), 15e6);

        vm.prank(creator);
        pool.voteExtendCycle(false);

        uint256 balanceBefore = token.balanceOf(creator);

        vm.prank(creator);
        pool.claimYield();

        assertEq(token.balanceOf(creator), balanceBefore + 15e6);
        assertEq(pool.claimableYield(creator), 0);
    }

    function testArchivedPoolAllowsYieldAndArchiveRefundClaimsTogether() external {
        _finishBidPeriod(member1, 10e6);
        _archiveCurrentPeriodOnMemberDefault(member2);

        assertEq(pool.claimableYield(creator), 5e6);
        assertEq(pool.claimableArchiveRefund(creator), CONTRIBUTION);

        uint256 balanceBefore = token.balanceOf(creator);

        vm.prank(creator);
        pool.claimYield();
        vm.prank(creator);
        pool.claimArchiveRefund();

        assertEq(token.balanceOf(creator), balanceBefore + 5e6 + CONTRIBUTION);
        assertEq(pool.claimableYield(creator), 0);
        assertEq(pool.claimableArchiveRefund(creator), 0);
    }

    function testLeaveAfterArchiveRequiresYieldClaimFirst() external {
        _finishBidPeriod(member1, 10e6);
        _archiveCurrentPeriodOnMemberDefault(member2);

        vm.prank(creator);
        pool.claimArchiveRefund();

        vm.prank(creator);
        vm.expectRevert(Errors.InvalidState.selector);
        pool.leaveAfterArchive();

        vm.prank(creator);
        pool.claimYield();
        vm.prank(creator);
        pool.leaveAfterArchive();

        assertTrue(pool.hasLeftArchive(creator));
    }

    function _finishBidPeriod(address bidder, uint256 discount) internal {
        (uint64 payoutDeadline,) = _reachPayoutOpenWithBid(bidder, discount, false);

        vm.prank(bidder);
        pool.claimPayout();

        vm.warp(uint256(payoutDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();
    }

    function _archiveCurrentPeriodOnMemberDefault(address defaultedMember) internal {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();

        (,, uint64 contributionDeadline,,,,,,,,) = pool.periodInfo(pool.currentCycle(), pool.currentPeriod());
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(creator);
        pool.markDefaultAndArchive(defaultedMember);
    }

    function _reachPayoutOpenWithBid(address bidder, uint256 discount, bool expectYieldEvents)
        internal
        returns (uint64 payoutDeadline, uint256 share)
    {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();
        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(bidder);
        pool.submitDiscountBid(discount);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        share = discount / (pool.activeMemberCount() - 1);

        if (expectYieldEvents) {
            if (bidder != creator) {
                vm.expectEmit(true, true, true, true, address(pool));
                emit ChainoraYieldAccrued(pool.currentCycle(), pool.currentPeriod(), creator, share);
            }

            if (bidder != member1) {
                vm.expectEmit(true, true, true, true, address(pool));
                emit ChainoraYieldAccrued(pool.currentCycle(), pool.currentPeriod(), member1, share);
            }

            if (bidder != member2) {
                vm.expectEmit(true, true, true, true, address(pool));
                emit ChainoraYieldAccrued(pool.currentCycle(), pool.currentPeriod(), member2, share);
            }
        }

        vm.prank(creator);
        pool.syncRuntime();

        status = _currentRuntimeStatus();
        payoutDeadline = status.payoutDeadline;
    }
}
