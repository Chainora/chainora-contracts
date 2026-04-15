// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaFactoryTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testCreatePoolSuccessWithVerifiedCreator() external {
        _verifyUser(member1);
        reputationAdapter.setScore(member1, 25);

        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            minReputation: 24,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days
        });

        vm.prank(member1);
        (address secondPool, uint256 secondPoolId) = factory.createPool(cfg);

        assertEq(secondPoolId, 2);
        assertEq(factory.poolById(2), secondPool);
        assertEq(uint256(ChainoraRoscaPool(secondPool).maxCycles()), uint256(cfg.targetMembers));
        assertEq(ChainoraRoscaPool(secondPool).memberReputationSnapshot(member1), 25);
    }

    function testCreatePoolSucceedsWhenCreatorScoreEqualsMinReputation() external {
        _verifyUser(member1);
        reputationAdapter.setScore(member1, 10);

        vm.prank(member1);
        (address secondPool,) = factory.createPool(_defaultPoolConfig(3, 10));

        assertEq(ChainoraRoscaPool(secondPool).memberReputationSnapshot(member1), 10);
    }

    function testPrivatePoolDoesNotAppearInRecruitingCatalog() external {
        _verifyUser(member1);

        (ChainoraRoscaPool secondPool, uint256 secondPoolId) = _createPoolFor(member1, false, 3);
        Types.PoolDiscoveryView memory listing = factory.recruitingPool(secondPoolId);

        assertEq(factory.recruitingPoolCount(), 0);
        assertEq(listing.pool, address(secondPool));
        assertFalse(listing.publicRecruitment);
        assertFalse(listing.listed);
        assertEq(listing.activeMemberCount, 1);
    }

    function testCreatePoolDoesNotPullCreatorContributionUpfront() external {
        _verifyUser(member1);

        uint256 creatorBalanceBefore = token.balanceOf(member1);

        vm.prank(member1);
        (address secondPool,) = factory.createPool(_defaultPoolConfig(3));

        assertEq(token.balanceOf(member1), creatorBalanceBefore);
        assertEq(token.balanceOf(secondPool), 0);
    }

    function testPublicPoolAppearsInRecruitingCatalog() external {
        _verifyUser(member1);

        (ChainoraRoscaPool secondPool, uint256 secondPoolId) = _createPoolFor(member1, true, 3);
        Types.PoolDiscoveryView memory listing = factory.recruitingPool(secondPoolId);

        assertEq(factory.recruitingPoolCount(), 1);
        assertEq(listing.poolId, secondPoolId);
        assertEq(listing.pool, address(secondPool));
        assertEq(listing.creator, member1);
        assertTrue(listing.publicRecruitment);
        assertTrue(listing.listed);
        assertEq(uint256(listing.poolStatus), uint256(Types.PoolStatus.Forming));
        assertEq(listing.activeMemberCount, 1);
        assertEq(listing.targetMembers, 3);
        assertEq(listing.contributionAmount, CONTRIBUTION);
        assertEq(listing.minReputation, 0);
    }

    function testRecruitingPoolsPaginationReturnsPublicPoolsInCreationOrder() external {
        _verifyUser(member1);
        _verifyUser(member2);

        (, uint256 secondPoolId) = _createPoolFor(member1, true, 3);
        (, uint256 thirdPoolId) = _createPoolFor(member2, true, 4);

        Types.PoolDiscoveryView[] memory firstPage = factory.recruitingPools(0, 1);
        Types.PoolDiscoveryView[] memory secondPage = factory.recruitingPools(1, 2);

        assertEq(factory.recruitingPoolCount(), 2);
        assertEq(firstPage.length, 1);
        assertEq(secondPage.length, 1);
        assertEq(firstPage[0].poolId, secondPoolId);
        assertEq(secondPage[0].poolId, thirdPoolId);
    }

    function testSyncRecruitingPoolRejectsUnknownCaller() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.syncRecruitingPool();
    }

    function testPublicPoolIsRemovedFromRecruitingCatalogWhenFull() external {
        _verifyUser(member1);

        (ChainoraRoscaPool secondPool, uint256 secondPoolId) = _createPoolFor(member1, true, 3);
        _approvePoolFor(address(secondPool), member2);
        _approvePoolFor(address(secondPool), outsider);

        vm.prank(member1);
        uint256 firstInvite = secondPool.proposeInvite(member2);
        vm.prank(member1);
        secondPool.voteInvite(firstInvite, true);
        vm.prank(member2);
        secondPool.acceptInvite(firstInvite);

        assertEq(factory.recruitingPoolCount(), 1);

        _verifyUser(outsider);

        vm.prank(member1);
        uint256 secondInvite = secondPool.proposeInvite(outsider);
        vm.prank(member1);
        secondPool.voteInvite(secondInvite, true);
        vm.prank(member2);
        secondPool.voteInvite(secondInvite, true);
        vm.prank(outsider);
        secondPool.acceptInvite(secondInvite);

        Types.PoolDiscoveryView memory listing = factory.recruitingPool(secondPoolId);
        assertEq(factory.recruitingPoolCount(), 0);
        assertFalse(listing.listed);
        assertEq(uint256(listing.poolStatus), uint256(Types.PoolStatus.Active));
        assertEq(listing.activeMemberCount, 3);
    }

    function testCreatePoolRevertsForUnverifiedCreator() external {
        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            minReputation: 0,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days
        });

        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.createPool(cfg);
    }

    function testRegistrySetterRequiresTimelockCaller() external {
        vm.prank(outsider);
        vm.expectRevert(Errors.Unauthorized.selector);
        registry.setStablecoin(address(token));
    }

    function testCreatePoolRevertsWhenNoIdleWindow() external {
        _verifyUser(member1);

        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            minReputation: 0,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 4 days,
            auctionWindow: 3 days
        });

        vm.prank(member1);
        vm.expectRevert(Errors.InvalidConfig.selector);
        factory.createPool(cfg);
    }

    function testCreatePoolRevertsWhenTargetMembersExceedsDerivedMaxCyclesRange() external {
        _verifyUser(member1);

        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            minReputation: 0,
            targetMembers: 256,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days
        });

        vm.prank(member1);
        vm.expectRevert(Errors.InvalidConfig.selector);
        factory.createPool(cfg);
    }

    function testCreatePoolRevertsAfterVerificationIsRevoked() external {
        _verifyUser(member1);

        vm.prank(address(timelock));
        deviceAdapter.revokeUser(member1);

        vm.prank(member1);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.createPool(_defaultPoolConfig(3));
    }

    function testCreatePoolRevertsWhenCreatorScoreIsBelowMinReputation() external {
        _verifyUser(member1);
        reputationAdapter.setScore(member1, 9);

        vm.prank(member1);
        vm.expectRevert(Errors.InsufficientReputation.selector);
        factory.createPool(_defaultPoolConfig(3, 10));
    }

    function testCreatePoolSucceedsWithoutReputationAdapterWhenMinReputationIsZero() external {
        _verifyUser(member1);

        vm.prank(address(timelock));
        registry.setReputationAdapter(address(0));

        vm.prank(member1);
        (address secondPool,) = factory.createPool(_defaultPoolConfig(3, 0));

        assertEq(ChainoraRoscaPool(secondPool).memberReputationSnapshot(member1), 0);
    }
}
