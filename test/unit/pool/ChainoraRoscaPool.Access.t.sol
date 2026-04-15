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
        uint64 startAt = _reachPayoutOpenWithBid();

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.finalizePeriod();

        vm.warp(uint256(startAt) + uint256(pool.periodDuration()) + 1);

        vm.prank(member1);
        pool.finalizePeriod();

        assertEq(pool.currentPeriod(), 2);
    }

    function testFinalizeRevertsBeforePeriodEnd() external {
        _reachPayoutOpenWithBid();

        vm.prank(member1);
        vm.expectRevert(Errors.DeadlineNotReached.selector);
        pool.finalizePeriod();
    }

    function _reachPayoutOpenWithBid() internal returns (uint64 startAt) {
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

        vm.prank(member1);
        pool.claimPayout();
    }
}
