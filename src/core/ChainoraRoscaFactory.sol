// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {Clones} from "src/libraries/Clones.sol";
import {IChainoraProtocolRegistry} from "src/core/IChainoraProtocolRegistry.sol";
import {IChainoraDeviceAdapter} from "src/adapters/interfaces/IChainoraDeviceAdapter.sol";
import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";
import {IChainoraRoscaPool} from "src/pool/IChainoraRoscaPool.sol";

contract ChainoraRoscaFactory is Events {
    using Clones for address;

    struct PoolMetadata {
        address creator;
        bool publicRecruitment;
        uint16 targetMembers;
        uint256 contributionAmount;
        uint256 minReputation;
    }

    address public timelock;
    address public registry;
    address public poolImplementation;

    address public implementation;

    uint256 public poolCount;
    mapping(uint256 => address) public poolById;
    mapping(address => uint256) public poolIdByAddress;

    mapping(uint256 => PoolMetadata) private _poolMetadata;
    uint256[] private _recruitingPoolIds;
    mapping(uint256 => uint256) private _recruitingPoolIndexPlusOne;

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
        return _createPool(config, false);
    }

    function createPool(Types.PoolConfig calldata config, bool publicRecruitment)
        external
        returns (address pool, uint256 poolId)
    {
        return _createPool(config, publicRecruitment);
    }

    function recruitingPoolCount() external view returns (uint256) {
        return _recruitingPoolIds.length;
    }

    function recruitingPools(uint256 offset, uint256 limit)
        external
        view
        returns (Types.PoolDiscoveryView[] memory pools)
    {
        uint256 total = _recruitingPoolIds.length;
        if (offset >= total || limit == 0) {
            return new Types.PoolDiscoveryView[](0);
        }

        uint256 end = offset + limit;
        if (end > total) end = total;

        pools = new Types.PoolDiscoveryView[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            pools[i - offset] = _buildPoolDiscoveryView(_recruitingPoolIds[i]);
        }
    }

    function recruitingPool(uint256 poolId) external view returns (Types.PoolDiscoveryView memory poolView) {
        poolView = _buildPoolDiscoveryView(poolId);
    }

    function syncRecruitingPool() external {
        uint256 poolId = poolIdByAddress[msg.sender];
        if (poolId == 0 || poolById[poolId] != msg.sender) revert Errors.Unauthorized();

        if (_isRecruitingPool(poolId, msg.sender)) {
            _addRecruitingPool(poolId);
        } else {
            _removeRecruitingPool(poolId);
        }
    }

    function _createPool(Types.PoolConfig calldata config, bool publicRecruitment)
        internal
        returns (address pool, uint256 poolId)
    {
        _validateConfig(config);

        IChainoraProtocolRegistry protocolRegistry = IChainoraProtocolRegistry(registry);
        address stablecoin = protocolRegistry.stablecoin();
        if (stablecoin == address(0)) revert Errors.InvalidConfig();

        address device = protocolRegistry.deviceAdapter();
        if (device != address(0)) {
            bool verified = IChainoraDeviceAdapter(device).isDeviceVerified(msg.sender);
            if (!verified) revert Errors.Unauthorized();
        }

        uint256 creatorReputationSnapshot = _reputationScore(protocolRegistry.reputationAdapter(), msg.sender);
        if (creatorReputationSnapshot <= config.minReputation) revert Errors.InsufficientReputation();

        pool = poolImplementation.clone();
        poolId = ++poolCount;
        poolById[poolId] = pool;
        poolIdByAddress[pool] = poolId;
        _poolMetadata[poolId] = PoolMetadata({
            creator: msg.sender,
            publicRecruitment: publicRecruitment,
            targetMembers: config.targetMembers,
            contributionAmount: config.contributionAmount,
            minReputation: config.minReputation
        });

        Types.PoolInitConfig memory initConfig = Types.PoolInitConfig({
            poolId: poolId,
            creator: msg.sender,
            registry: registry,
            stablecoin: stablecoin,
            publicRecruitment: publicRecruitment,
            creatorReputationSnapshot: creatorReputationSnapshot,
            config: config
        });

        IChainoraRoscaPool(pool).initialize(initConfig);

        if (_isRecruitingPool(poolId, pool)) {
            _addRecruitingPool(poolId);
        }

        emit ChainoraPoolCreated(poolId, pool, msg.sender);
    }

    function _buildPoolDiscoveryView(uint256 poolId) private view returns (Types.PoolDiscoveryView memory poolView) {
        address pool = poolById[poolId];
        if (pool == address(0)) revert Errors.InvalidConfig();

        PoolMetadata storage metadata = _poolMetadata[poolId];
        IChainoraRoscaPool roscaPool = IChainoraRoscaPool(pool);

        poolView = Types.PoolDiscoveryView({
            poolId: poolId,
            pool: pool,
            creator: metadata.creator,
            publicRecruitment: metadata.publicRecruitment,
            listed: _recruitingPoolIndexPlusOne[poolId] != 0,
            poolStatus: roscaPool.poolStatus(),
            activeMemberCount: roscaPool.activeMemberCount(),
            targetMembers: metadata.targetMembers,
            contributionAmount: metadata.contributionAmount,
            minReputation: metadata.minReputation
        });
    }

    function _isRecruitingPool(uint256 poolId, address pool) private view returns (bool) {
        PoolMetadata storage metadata = _poolMetadata[poolId];
        if (!metadata.publicRecruitment) return false;

        IChainoraRoscaPool roscaPool = IChainoraRoscaPool(pool);
        return
            roscaPool.poolStatus() == Types.PoolStatus.Forming && roscaPool.activeMemberCount() < metadata.targetMembers;
    }

    function _addRecruitingPool(uint256 poolId) private {
        if (_recruitingPoolIndexPlusOne[poolId] != 0) return;

        _recruitingPoolIds.push(poolId);
        _recruitingPoolIndexPlusOne[poolId] = _recruitingPoolIds.length;
    }

    function _removeRecruitingPool(uint256 poolId) private {
        uint256 indexPlusOne = _recruitingPoolIndexPlusOne[poolId];
        if (indexPlusOne == 0) return;

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = _recruitingPoolIds.length - 1;
        if (index != lastIndex) {
            uint256 movedPoolId = _recruitingPoolIds[lastIndex];
            _recruitingPoolIds[index] = movedPoolId;
            _recruitingPoolIndexPlusOne[movedPoolId] = indexPlusOne;
        }

        _recruitingPoolIds.pop();
        delete _recruitingPoolIndexPlusOne[poolId];
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

    function _reputationScore(address reputationAdapter, address account) private view returns (uint256) {
        if (reputationAdapter == address(0)) return 0;
        return IChainoraReputationAdapter(reputationAdapter).scoreOf(account);
    }
}
