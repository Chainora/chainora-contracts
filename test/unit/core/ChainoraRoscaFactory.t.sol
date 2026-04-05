// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaFactoryTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testCreatePoolSuccessWithVerifiedCreator() external {
        deviceAdapter.setVerified(member1, true);

        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days,
            maxCycles: 2
        });

        vm.prank(member1);
        (address secondPool, uint256 secondPoolId) = factory.createPool(cfg);

        assertEq(secondPoolId, 2);
        assertEq(factory.poolById(2), secondPool);
    }

    function testCreatePoolRevertsForUnverifiedCreator() external {
        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days,
            maxCycles: 2
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
}
