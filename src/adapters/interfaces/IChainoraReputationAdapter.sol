// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainoraReputationAdapter {
    function snapshotPeriodScores(uint256 poolId, uint256 cycleId, uint256 periodId, address[] calldata members)
        external
        returns (bytes32 snapshotId);

    function scoreOfAt(bytes32 snapshotId, address user) external view returns (uint256);
}
