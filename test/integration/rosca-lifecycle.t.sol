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

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();

        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(member1);
        pool.submitDiscountBid(10e6);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();

        (,,,, address recipient,,,, uint256 payoutAmount, bool payoutClaimed,) =
            pool.periodInfo(pool.currentCycle(), pool.currentPeriod());
        assertEq(recipient, member1);
        assertFalse(payoutClaimed);

        uint256 balanceBefore = token.balanceOf(recipient);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.payoutDeadline) + 1);

        vm.prank(member2);
        pool.syncRuntime();

        assertEq(token.balanceOf(recipient), balanceBefore + payoutAmount);
        assertEq(pool.currentPeriod(), 2);
    }

    function _finishPeriodWithBid(address bidder, uint256 discount) internal {
        _contributeAllActive();

        Types.RuntimeStatusView memory status = _currentRuntimeStatus();

        vm.warp(uint256(status.contributionDeadline) + 1);

        vm.prank(bidder);
        pool.submitDiscountBid(discount);

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.auctionDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();

        vm.prank(bidder);
        pool.claimPayout();

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.payoutDeadline) + 1);

        vm.prank(member1);
        pool.syncRuntime();
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

        (,,,, address recipient,,,,,,) = pool.periodInfo(pool.currentCycle(), pool.currentPeriod());
        assertEq(recipient, expectedRecipient);

        vm.prank(expectedRecipient);
        pool.claimPayout();

        status = _currentRuntimeStatus();
        vm.warp(uint256(status.payoutDeadline) + 1);

        vm.prank(creator);
        pool.syncRuntime();
    }
}
