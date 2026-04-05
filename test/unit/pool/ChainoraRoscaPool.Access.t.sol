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
        vm.expectRevert(Errors.NotMember.selector);
        pool.archive();
    }

    function testOnlyActiveMemberCanFinalize() external {
        _contributeAllActive();

        (,, uint64 contributionDeadline, uint64 auctionDeadline,,,,,,,) = pool.periodInfo(1, 1);
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        vm.warp(uint256(auctionDeadline) + 1);

        vm.prank(creator);
        pool.closeAuctionAndSelectRecipient();

        vm.prank(member1);
        pool.claimPayout();

        vm.prank(outsider);
        vm.expectRevert(Errors.NotActiveMember.selector);
        pool.finalizePeriod();
    }
}
