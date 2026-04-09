// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {Clones} from "src/libraries/Clones.sol";
import {IChainoraProtocolRegistry} from "src/core/IChainoraProtocolRegistry.sol";
import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";
import {IChainoraRoscaPool} from "src/pool/IChainoraRoscaPool.sol";

contract ChainoraRoscaFactory is Events {
    using Clones for address;

    address public timelock;
    address public registry;
    address public poolImplementation;

    address public implementation;

    uint256 public poolCount;
    mapping(uint256 => address) public poolById;

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Errors.Unauthorized();
        _;
    }

    constructor(address timelock_, address registry_, address poolImplementation_) {
        if (timelock_ == address(0) || registry_ == address(0) || poolImplementation_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        timelock = timelock_;
        registry = registry_;
        poolImplementation = poolImplementation_;
    }

    function setRegistry(address newRegistry) external onlyTimelock {
        if (newRegistry == address(0)) revert Errors.ZeroAddress();
        registry = newRegistry;
    }

    function setPoolImplementation(address newImplementation) external onlyTimelock {
        if (newImplementation == address(0)) revert Errors.ZeroAddress();
        poolImplementation = newImplementation;
    }

    function upgradeTo(address newImplementation) external onlyTimelock {
        if (newImplementation.code.length == 0) revert Errors.UpgradeImplementationInvalid();
        implementation = newImplementation;
        emit ChainoraUpgraded(newImplementation);
    }

    function createPool(Types.PoolConfig calldata config) external returns (address pool, uint256 poolId) {
        _validateConfig(config);

        IChainoraProtocolRegistry protocolRegistry = IChainoraProtocolRegistry(registry);
        address stablecoin = protocolRegistry.stablecoin();
        if (stablecoin == address(0)) revert Errors.InvalidConfig();

        address device = protocolRegistry.deviceAdapter();
        if (device != address(0)) {
            bool verified = IChainoraDeviceAdapter(device).isDeviceVerified(msg.sender);
            if (!verified) revert Errors.Unauthorized();
        }

        pool = poolImplementation.clone();
        poolId = ++poolCount;
        poolById[poolId] = pool;

        Types.PoolInitConfig memory initConfig = Types.PoolInitConfig({
            poolId: poolId, creator: msg.sender, registry: registry, stablecoin: stablecoin, config: config
        });

        IChainoraRoscaPool(pool).initialize(initConfig);

        emit ChainoraPoolCreated(poolId, pool, msg.sender);
    }

    function _validateConfig(Types.PoolConfig calldata config) private pure {
        if (config.contributionAmount == 0) revert Errors.InvalidConfig();
        if (config.targetMembers < 2) revert Errors.InvalidConfig();
        if (config.targetMembers > type(uint8).max) revert Errors.InvalidConfig();
        if (config.periodDuration == 0 || config.contributionWindow == 0 || config.auctionWindow == 0) {
            revert Errors.InvalidConfig();
        }
        if (config.contributionWindow + config.auctionWindow >= config.periodDuration) {
            revert Errors.InvalidConfig();
        }
    }
}
