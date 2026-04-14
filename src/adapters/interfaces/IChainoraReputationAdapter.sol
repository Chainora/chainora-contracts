// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IChainoraReputationAdapter {
    struct ReputationScoreUpdate {
        address user;
        uint256 score;
        uint256 nonce;
    }

    function submitScores(ReputationScoreUpdate[] calldata updates, uint64 deadline, bytes calldata signature) external;

    function scoreOf(address user) external view returns (uint256);

    function nextNonce(address user) external view returns (uint256);

    function snapshotPeriodScores(uint256 poolId, uint256 cycleId, uint256 periodId, address[] calldata members)
        external
        returns (bytes32 snapshotId);

    function scoreOfAt(bytes32 snapshotId, address user) external view returns (uint256);
}
