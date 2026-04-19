// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ExtensionOrArchiveIntegrationTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testUnanimousExtendStartsNewCycle() external {
        _finishPeriodWithFallback(member1, 1000);
        _finishPeriodWithFallback(member2, 2000);
        _finishPeriodWithFallback(creator, 3000);

        assertTrue(pool.cycleCompleted());

        vm.prank(creator);
        pool.voteExtendCycle(true);
        vm.prank(member1);
        pool.voteExtendCycle(true);
        vm.prank(member2);
        pool.voteExtendCycle(true);

        assertEq(pool.currentCycle(), 2);
        assertEq(pool.currentPeriod(), 1);
        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Active));
        assertFalse(pool.cycleCompleted());
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
