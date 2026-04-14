// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraProtocolTimelock} from "src/governance/ChainoraProtocolTimelock.sol";
import {ChainoraProtocolRegistry} from "src/core/ChainoraProtocolRegistry.sol";
import {ChainoraRoscaFactory} from "src/core/ChainoraRoscaFactory.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";
import {ChainoraDeviceAdapter} from "src/adapters/ChainoraDeviceAdapter.sol";
import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";
import {ChainoraMockReputationAdapter} from "src/adapters/mocks/ChainoraMockReputationAdapter.sol";
import {ChainoraMockStakingAdapter4626} from "src/adapters/mocks/ChainoraMockStakingAdapter4626.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

abstract contract ChainoraTestBase is Test {
    uint256 internal constant CONTRIBUTION = 100e6;
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant DEVICE_VERIFICATION_ATTESTATION_TYPEHASH =
        keccak256("DeviceVerificationAttestation(address user,uint256 nonce,uint64 deadline)");
    uint256 internal constant DEVICE_VERIFIER_KEY = 0xA11CEBEEF;

    address internal creator = address(0xA11CE);
    address internal member1 = address(0xB0B);
    address internal member2 = address(0xCAFE);
    address internal outsider = address(0xDEAD);
    address internal deviceVerifier;

    MockERC20 internal token;
    ChainoraDeviceAdapter internal deviceAdapter;
    ChainoraMockReputationAdapter internal reputationAdapter;
    ChainoraMockStakingAdapter4626 internal stakingAdapter;

    ChainoraProtocolTimelock internal timelock;
    ChainoraProtocolRegistry internal registry;
    ChainoraRoscaFactory internal factory;
    ChainoraRoscaPool internal poolImplementation;
    ChainoraRoscaPool internal pool;

    function _setUpProtocolAndPool() internal {
        token = new MockERC20("Mock USDC", "mUSDC", 6);
        deviceVerifier = vm.addr(DEVICE_VERIFIER_KEY);

        address[] memory roleHolders = new address[](1);
        roleHolders[0] = address(this);

        timelock = new ChainoraProtocolTimelock(0, address(this), roleHolders, roleHolders, roleHolders);
        registry = new ChainoraProtocolRegistry(address(timelock), address(0), address(0), address(0), address(0));

        deviceAdapter = new ChainoraDeviceAdapter(address(timelock));
        reputationAdapter = new ChainoraMockReputationAdapter();
        stakingAdapter = new ChainoraMockStakingAdapter4626(address(token));
        reputationAdapter.setScore(creator, 1);
        reputationAdapter.setScore(member1, 1);
        reputationAdapter.setScore(member2, 1);
        reputationAdapter.setScore(outsider, 1);

        vm.startPrank(address(timelock));
        registry.setStablecoin(address(token));
        registry.setDeviceAdapter(address(deviceAdapter));
        registry.setReputationAdapter(address(reputationAdapter));
        registry.setStakingAdapter(address(stakingAdapter));
        deviceAdapter.setTrustVerifier(deviceVerifier, true);
        vm.stopPrank();

        poolImplementation = new ChainoraRoscaPool();
        factory = new ChainoraRoscaFactory(address(timelock), address(registry), address(poolImplementation));

        _verifyUser(creator);

        _mintAndApproveFactory(creator);
        _mintAndApproveFactory(member1);
        _mintAndApproveFactory(member2);
        _mintAndApproveFactory(outsider);

        Types.PoolConfig memory cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            minReputation: 0,
            targetMembers: 3,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days
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

    function _approvePoolFor(address poolAddr, address user) internal {
        vm.prank(user);
        token.approve(poolAddr, type(uint256).max);
    }

    function _defaultPoolConfig(uint16 targetMembers) internal pure returns (Types.PoolConfig memory cfg) {
        return _defaultPoolConfig(targetMembers, 0);
    }

    function _defaultPoolConfig(uint16 targetMembers, uint256 minReputation)
        internal
        pure
        returns (Types.PoolConfig memory cfg)
    {
        cfg = Types.PoolConfig({
            contributionAmount: CONTRIBUTION,
            minReputation: minReputation,
            targetMembers: targetMembers,
            periodDuration: 7 days,
            contributionWindow: 2 days,
            auctionWindow: 1 days
        });
    }

    function _createPoolFor(address poolCreator, bool publicRecruitment, uint16 targetMembers)
        internal
        returns (ChainoraRoscaPool newPool, uint256 newPoolId)
    {
        return _createPoolFor(poolCreator, publicRecruitment, targetMembers, 0);
    }

    function _createPoolFor(address poolCreator, bool publicRecruitment, uint16 targetMembers, uint256 minReputation)
        internal
        returns (ChainoraRoscaPool newPool, uint256 newPoolId)
    {
        Types.PoolConfig memory cfg = _defaultPoolConfig(targetMembers, minReputation);

        vm.prank(poolCreator);
        (address poolAddr, uint256 poolId) = factory.createPool(cfg, publicRecruitment);

        newPool = ChainoraRoscaPool(poolAddr);
        newPoolId = poolId;
    }

    function _formThreeMemberPool() internal {
        vm.prank(creator);
        uint256 p1 = pool.proposeInvite(member1);

        vm.prank(creator);
        pool.voteInvite(p1, true);

        vm.prank(member1);
        pool.acceptInvite(p1);

        vm.prank(creator);
        uint256 p2 = pool.proposeInvite(member2);

        vm.prank(creator);
        pool.voteInvite(p2, true);
        vm.prank(member1);
        pool.voteInvite(p2, true);

        vm.prank(member2);
        pool.acceptInvite(p2);
    }

    function _contributeAllActive() internal {
        vm.prank(creator);
        pool.contribute();
        vm.prank(member1);
        pool.contribute();
        vm.prank(member2);
        pool.contribute();
    }

    function _verifyUser(address user) internal {
        (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature) =
            _signedDeviceVerification(user, DEVICE_VERIFIER_KEY);

        vm.prank(user);
        deviceAdapter.submitVerification(attestation, signature);
    }

    function _deviceVerificationAttestation(address user)
        internal
        view
        returns (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation)
    {
        return _deviceVerificationAttestation(user, deviceAdapter.nextNonce(user), uint64(block.timestamp + 1 days));
    }

    function _deviceVerificationAttestation(address user, uint256 nonce, uint64 deadline)
        internal
        pure
        returns (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation)
    {
        attestation =
            IChainoraDeviceAdapter.DeviceVerificationAttestation({user: user, nonce: nonce, deadline: deadline});
    }

    function _signedDeviceVerification(address user, uint256 signerKey)
        internal
        returns (IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation, bytes memory signature)
    {
        attestation = _deviceVerificationAttestation(user);
        signature = _signDeviceVerification(attestation, signerKey);
    }

    function _signDeviceVerification(
        IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation,
        uint256 signerKey
    ) internal returns (bytes memory signature) {
        bytes32 digest = _deviceVerificationDigest(attestation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _deviceVerificationDigest(IChainoraDeviceAdapter.DeviceVerificationAttestation memory attestation)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ChainoraDeviceAdapter")),
                keccak256(bytes("1")),
                block.chainid,
                address(deviceAdapter)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                DEVICE_VERIFICATION_ATTESTATION_TYPEHASH, attestation.user, attestation.nonce, attestation.deadline
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
