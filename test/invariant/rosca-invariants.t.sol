// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract RoscaInvariantsTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testInvariantOneRecipientPerPeriod() external {
        _contributeAllActive();
        (,, uint64 contributionDeadline, uint64 auctionDeadline,,,,,,,) = pool.periodInfo(1, 1);

        vm.warp(uint256(contributionDeadline) + 1);
        vm.prank(member1);
        pool.submitDiscountBid(5e6);

        vm.warp(uint256(auctionDeadline) + 1);
        vm.prank(creator);
        pool.closeAuctionAndSelectRecipient();

        (,,,, address recipient,,,,,,) = pool.periodInfo(1, 1);
        assertTrue(recipient == member1 || recipient == creator || recipient == member2);

        assertTrue(pool.hasReceivedInCycle(1, recipient));
    }

    function testInvariantArchivedBlocksRuntimeActions() external {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();

        (,, uint64 contributionDeadline,,,,,,,,) = pool.periodInfo(1, 1);
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(creator);
        pool.markDefaultAndArchive(member2);

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Archived));

        vm.prank(member1);
        vm.expectRevert(Errors.InvalidState.selector);
        pool.contribute();
    }

    function testInvariantNonMemberCannotFinalize() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.finalizePeriod();
    }
}
