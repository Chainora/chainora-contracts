// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Types} from "src/libraries/Types.sol";
import {ChainoraRoscaFactory} from "src/core/ChainoraRoscaFactory.sol";

contract CreatePool is Script {
    function run() external returns (address pool, uint256 poolId) {
        uint256 signerKey = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("CHAINORA_FACTORY");

        Types.PoolConfig memory config = Types.PoolConfig({
            contributionAmount: vm.envOr("CHAINORA_CONTRIBUTION_AMOUNT", uint256(100e6)),
            targetMembers: uint16(vm.envOr("CHAINORA_TARGET_MEMBERS", uint256(5))),
            periodDuration: uint32(vm.envOr("CHAINORA_PERIOD_DURATION", uint256(7 days))),
            contributionWindow: uint32(vm.envOr("CHAINORA_CONTRIBUTION_WINDOW", uint256(2 days))),
            auctionWindow: uint32(vm.envOr("CHAINORA_AUCTION_WINDOW", uint256(1 days))),
            maxCycles: uint8(vm.envOr("CHAINORA_MAX_CYCLES", uint256(2)))
        });

        vm.startBroadcast(signerKey);
        (pool, poolId) = ChainoraRoscaFactory(factoryAddr).createPool(config);
        vm.stopBroadcast();

        console2.log("pool", pool);
        console2.log("poolId", poolId);
    }
}
