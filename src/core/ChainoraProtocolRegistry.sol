// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";

contract ChainoraProtocolRegistry is Events {
    address public timelock;
    address public stablecoin;
    address public deviceAdapter;
    address public reputationAdapter;
    address public stakingAdapter;

    address public implementation;

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Errors.Unauthorized();
        _;
    }

    constructor(
        address timelock_,
        address stablecoin_,
        address deviceAdapter_,
        address reputationAdapter_,
        address stakingAdapter_
    ) {
        if (timelock_ == address(0)) revert Errors.ZeroAddress();
        timelock = timelock_;
        stablecoin = stablecoin_;
        deviceAdapter = deviceAdapter_;
        reputationAdapter = reputationAdapter_;
        stakingAdapter = stakingAdapter_;
    }

    function setStablecoin(address newStablecoin) external onlyTimelock {
        if (newStablecoin == address(0)) revert Errors.ZeroAddress();
        emit ChainoraRegistryStablecoinSet(stablecoin, newStablecoin);
        stablecoin = newStablecoin;
    }

    function setDeviceAdapter(address newAdapter) external onlyTimelock {
        emit ChainoraRegistryDeviceAdapterSet(deviceAdapter, newAdapter);
        deviceAdapter = newAdapter;
    }

    function setReputationAdapter(address newAdapter) external onlyTimelock {
        emit ChainoraRegistryReputationAdapterSet(reputationAdapter, newAdapter);
        reputationAdapter = newAdapter;
    }

    function setStakingAdapter(address newAdapter) external onlyTimelock {
        emit ChainoraRegistryStakingAdapterSet(stakingAdapter, newAdapter);
        stakingAdapter = newAdapter;
    }

    function upgradeTo(address newImplementation) external onlyTimelock {
        if (newImplementation.code.length == 0) revert Errors.UpgradeImplementationInvalid();
        implementation = newImplementation;
        emit ChainoraUpgraded(newImplementation);
    }
}
