// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract PublicRecruitmentIntegrationTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testPublicPoolApplicationActivatesPoolAndRemovesListingWhenFull() external {
        _verifyUser(member1);
        _verifyUser(outsider);

        (ChainoraRoscaPool publicPool, uint256 publicPoolId) = _createPoolFor(member1, true, 2);
        _approvePoolFor(address(publicPool), outsider);

        assertEq(factory.recruitingPoolCount(), 1);

        vm.prank(outsider);
        uint256 requestId = publicPool.submitJoinRequest();

        vm.prank(member1);
        publicPool.voteJoinRequest(requestId, true);

        vm.prank(outsider);
        publicPool.acceptJoinRequestAndLockDeposit(requestId);

        Types.PoolDiscoveryView memory listing = factory.recruitingPool(publicPoolId);
        assertEq(factory.recruitingPoolCount(), 0);
        assertFalse(listing.listed);
        assertEq(uint256(listing.poolStatus), uint256(Types.PoolStatus.Active));
        assertEq(listing.activeMemberCount, 2);
        assertEq(publicPool.currentCycle(), 1);
        assertEq(publicPool.currentPeriod(), 1);
    }
}
