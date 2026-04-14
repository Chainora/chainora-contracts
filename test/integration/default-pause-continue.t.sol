// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract DefaultArchiveIntegrationTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testDefaultArchivesImmediatelyAndRefundsContributors() external {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();

        uint256 creatorBalanceBefore = token.balanceOf(creator);
        uint256 member1BalanceBefore = token.balanceOf(member1);
        uint256 member2BalanceBefore = token.balanceOf(member2);

        (,, uint64 contributionDeadline,,,,,,,,) = pool.periodInfo(1, 1);
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(creator);
        pool.markDefaultAndArchive(member2);

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Archived));
        assertEq(pool.claimableArchiveRefund(creator), CONTRIBUTION);
        assertEq(pool.claimableArchiveRefund(member1), CONTRIBUTION);
        assertEq(pool.claimableArchiveRefund(member2), 0);

        vm.prank(member2);
        vm.expectRevert(Errors.PayoutUnavailable.selector);
        pool.claimArchiveRefund();

        vm.prank(creator);
        pool.claimArchiveRefund();
        vm.prank(member1);
        pool.claimArchiveRefund();

        assertEq(token.balanceOf(creator), creatorBalanceBefore + CONTRIBUTION);
        assertEq(token.balanceOf(member1), member1BalanceBefore + CONTRIBUTION);
        assertEq(token.balanceOf(member2), member2BalanceBefore);
    }

    function testLeaveAfterArchiveRequiresRefundClaimFirst() external {
        vm.prank(creator);
        pool.contribute();

        (,, uint64 contributionDeadline,,,,,,,,) = pool.periodInfo(1, 1);
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(member1);
        pool.markDefaultAndArchive(member2);

        vm.prank(creator);
        vm.expectRevert(Errors.InvalidState.selector);
        pool.leaveAfterArchive();

        vm.prank(creator);
        pool.claimArchiveRefund();

        vm.prank(creator);
        pool.leaveAfterArchive();

        assertTrue(pool.hasLeftArchive(creator));
    }
}
