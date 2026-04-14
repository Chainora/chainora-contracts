// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraTestBase} from "test/helpers/ChainoraTestBase.t.sol";

contract ChainoraRoscaPoolInitTest is ChainoraTestBase {
    function setUp() external {
        _setUpProtocolAndPool();
    }

    function testInitializeAllowsCreatorScoreEqualToMinReputation() external {
        ChainoraRoscaPool newPool = new ChainoraRoscaPool();
        Types.PoolConfig memory cfg = _defaultPoolConfig(3, 10);
        Types.PoolInitConfig memory initConfig = Types.PoolInitConfig({
            poolId: 99,
            creator: member1,
            registry: address(registry),
            stablecoin: address(token),
            publicRecruitment: true,
            creatorReputationSnapshot: 10,
            config: cfg
        });

        newPool.initialize(initConfig);

        assertEq(newPool.creator(), member1);
        assertEq(newPool.memberReputationSnapshot(member1), 10);
        assertEq(newPool.minReputation(), 10);
    }
}
