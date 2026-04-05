// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainoraProtocolRegistry {
    function timelock() external view returns (address);

    function stablecoin() external view returns (address);

    function deviceAdapter() external view returns (address);

    function reputationAdapter() external view returns (address);

    function stakingAdapter() external view returns (address);
}
