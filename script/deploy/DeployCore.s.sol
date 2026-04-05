// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChainoraProtocolTimelock} from "src/governance/ChainoraProtocolTimelock.sol";
import {ChainoraProtocolRegistry} from "src/core/ChainoraProtocolRegistry.sol";
import {ChainoraRoscaFactory} from "src/core/ChainoraRoscaFactory.sol";
import {ChainoraRoscaPool} from "src/pool/ChainoraRoscaPool.sol";

contract DeployCore is Script {
    function run()
        external
        returns (
            ChainoraProtocolTimelock timelock,
            ChainoraProtocolRegistry registry,
            ChainoraRoscaFactory factory,
            ChainoraRoscaPool poolImplementation
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address multisig = vm.envOr("CHAINORA_MULTISIG", deployer);
        uint64 delaySeconds = uint64(vm.envOr("CHAINORA_TIMELOCK_DELAY", uint256(0)));

        address[] memory proposers = new address[](1);
        proposers[0] = multisig;

        address[] memory executors = new address[](1);
        executors[0] = multisig;

        address[] memory cancellers = new address[](1);
        cancellers[0] = multisig;

        vm.startBroadcast(deployerKey);

        timelock = new ChainoraProtocolTimelock(delaySeconds, multisig, proposers, executors, cancellers);
        registry = new ChainoraProtocolRegistry(address(timelock), address(0), address(0), address(0), address(0));
        poolImplementation = new ChainoraRoscaPool();
        factory = new ChainoraRoscaFactory(address(timelock), address(registry), address(poolImplementation));

        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("multisig", multisig);
        console2.log("timelock", address(timelock));
        console2.log("registry", address(registry));
        console2.log("poolImplementation", address(poolImplementation));
        console2.log("factory", address(factory));
    }
}
