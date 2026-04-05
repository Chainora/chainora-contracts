// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraProtocolTimelock} from "src/governance/ChainoraProtocolTimelock.sol";
import {ChainoraProtocolRegistry} from "src/core/ChainoraProtocolRegistry.sol";
import {ChainoraRoscaFactory} from "src/core/ChainoraRoscaFactory.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraMockDeviceAdapter} from "src/adapters/mocks/ChainoraMockDeviceAdapter.sol";
import {ChainoraMockReputationAdapter} from "src/adapters/mocks/ChainoraMockReputationAdapter.sol";
import {ChainoraMockStakingAdapter4626} from "src/adapters/mocks/ChainoraMockStakingAdapter4626.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

abstract contract ChainoraTestBase is Test {
    uint256 internal constant CONTRIBUTION = 100e6;

    address internal creator = address(0xA11CE);
    address internal member1 = address(0xB0B);
    address internal member2 = address(0xCAFE);
    address internal outsider = address(0xDEAD);

    MockERC20 internal token;
    ChainoraMockDeviceAdapter internal deviceAdapter;
    ChainoraMockReputationAdapter internal reputationAdapter;
    ChainoraMockStakingAdapter4626 internal stakingAdapter;

    ChainoraProtocolTimelock internal timelock;
    ChainoraProtocolRegistry internal registry;
    ChainoraRoscaFactory internal factory;
    ChainoraRoscaPool internal poolImplementation;
    ChainoraRoscaPool internal pool;

    function _setUpProtocolAndPool() internal {
        token = new MockERC20("Mock USDC", "mUSDC", 6);

        address[] memory roleHolders = new address[](1);
        roleHolders[0] = address(this);

        timelock = new ChainoraProtocolTimelock(0, address(this), roleHolders, roleHolders, roleHolders);
        registry = new ChainoraProtocolRegistry(address(timelock), address(0), address(0), address(0), address(0));

        deviceAdapter = new ChainoraMockDeviceAdapter();
        reputationAdapter = new ChainoraMockReputationAdapter();
        stakingAdapter = new ChainoraMockStakingAdapter4626(address(token));

        vm.startPrank(address(timelock));
        registry.setStablecoin(address(token));
        registry.setDeviceAdapter(address(deviceAdapter));
        registry.setReputationAdapter(address(reputationAdapter));
        registry.setStakingAdapter(address(stakingAdapter));
        vm.stopPrank();

        poolImplementation = new ChainoraRoscaPool();
        factory = new ChainoraRoscaFactory(address(timelock), address(registry), address(poolImplementation));

        deviceAdapter.setVerified(creator, true);

        _mintAndApproveFactory(creator);
        _mintAndApproveFactory(member1);
        _mintAndApproveFactory(member2);
        _mintAndApproveFactory(outsider);

        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days,
            maxCycles: 2
        });

        vm.prank(creator);
        (address poolAddr,) = factory.createPool(cfg);
        pool = ChainoraRoscaPool(poolAddr);

        _approvePool(creator);
        _approvePool(member1);
        _approvePool(member2);
        _approvePool(outsider);

        _formThreeMemberPool();
    }

    function _mintAndApproveFactory(address user) internal {
        token.mint(user, 1_000_000e6);
        vm.prank(user);
        token.approve(address(factory), type(uint256).max);
    }

    function _approvePool(address user) internal {
        vm.prank(user);
        token.approve(address(pool), type(uint256).max);
    }

    function _formThreeMemberPool() internal {
        vm.prank(creator);
        uint256 p1 = pool.proposeInvite(member1);

        vm.prank(creator);
        pool.voteInvite(p1, true);

        vm.prank(member1);
        pool.acceptInviteAndLockDeposit(p1);

        vm.prank(creator);
        uint256 p2 = pool.proposeInvite(member2);

        vm.prank(creator);
        pool.voteInvite(p2, true);
        vm.prank(member1);
        pool.voteInvite(p2, true);

        vm.prank(member2);
        pool.acceptInviteAndLockDeposit(p2);
    }

    function _contributeAllActive() internal {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();
        vm.prank(member2);
        pool.contribute();
    }
}
