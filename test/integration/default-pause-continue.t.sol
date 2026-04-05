// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract DefaultPauseContinueIntegrationTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testPauseAndContinueAfterDefault() external {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();

        (,, uint64 contributionDeadline,,,,,,,,) = pool.periodInfo(1, 1);
        vm.warp(uint256(contributionDeadline) + 1);

        vm.prank(creator);
        pool.markDefaultAndPause(member2);

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Paused));
        assertFalse(pool.isActiveMember(member2));

        vm.prank(creator);
        pool.voteContinueAfterPause(true);
        vm.prank(member1);
        pool.voteContinueAfterPause(true);

        assertEq(uint256(pool.poolStatus()), uint256(Types.PoolStatus.Active));
    }
}
