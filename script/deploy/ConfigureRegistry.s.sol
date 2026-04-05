// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChainoraProtocolRegistry} from "src/core/ChainoraProtocolRegistry.sol";
import {ChainoraProtocolTimelock} from "src/governance/ChainoraProtocolTimelock.sol";

contract ConfigureRegistry is Script {
    function run() external {
        uint256 signerKey = vm.envUint("PRIVATE_KEY");
        address registryAddr = vm.envAddress("CHAINORA_REGISTRY");
        address timelockAddr = vm.envAddress("CHAINORA_TIMELOCK");

        address stablecoin = vm.envOr("CHAINORA_STABLECOIN", address(0));
        address deviceAdapter = vm.envOr("CHAINORA_DEVICE_ADAPTER", address(0));
        address reputationAdapter = vm.envOr("CHAINORA_REPUTATION_ADAPTER", address(0));
        address stakingAdapter = vm.envOr("CHAINORA_STAKING_ADAPTER", address(0));

        uint64 delaySeconds = uint64(vm.envOr("CHAINORA_TIMELOCK_DELAY", uint256(0)));

        ChainoraProtocolRegistry registry = ChainoraProtocolRegistry(registryAddr);
        ChainoraProtocolTimelock timelock = ChainoraProtocolTimelock(payable(timelockAddr));

        vm.startBroadcast(signerKey);

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, registryAddr, block.timestamp));

        if (stablecoin != address(0)) {
            bytes memory data = abi.encodeCall(registry.setStablecoin, (stablecoin));
            _scheduleAndMaybeExecute(timelock, registryAddr, data, predecessor, salt, delaySeconds);
        }

        if (deviceAdapter != address(0)) {
            bytes memory data = abi.encodeCall(registry.setDeviceAdapter, (deviceAdapter));
            _scheduleAndMaybeExecute(timelock, registryAddr, data, predecessor, salt, delaySeconds);
        }

        if (reputationAdapter != address(0)) {
            bytes memory data = abi.encodeCall(registry.setReputationAdapter, (reputationAdapter));
            _scheduleAndMaybeExecute(timelock, registryAddr, data, predecessor, salt, delaySeconds);
        }

        if (stakingAdapter != address(0)) {
            bytes memory data = abi.encodeCall(registry.setStakingAdapter, (stakingAdapter));
            _scheduleAndMaybeExecute(timelock, registryAddr, data, predecessor, salt, delaySeconds);
        }

        vm.stopBroadcast();

        console2.log("configured registry", registryAddr);
    }

    function _scheduleAndMaybeExecute(
        ChainoraProtocolTimelock timelock,
        address target,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt,
        uint64 delaySeconds
    ) internal {
        timelock.schedule(target, 0, data, predecessor, salt, delaySeconds);

        if (delaySeconds == 0) {
            timelock.execute(target, 0, data, predecessor, salt);
        }
    }
}
