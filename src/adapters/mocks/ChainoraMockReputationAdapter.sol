// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChainoraReputationAdapter} from "src/adapters/interfaces/IChainoraReputationAdapter.sol";

contract ChainoraMockReputationAdapter is IChainoraReputationAdapter {
    mapping(address => uint256) private _liveScore;
    mapping(address => uint256) public nextNonce;
    mapping(bytes32 => mapping(address => uint256)) private _snapshotScore;
    uint256 private _snapshotNonce;

    function setScore(address user, uint256 score) external {
        _liveScore[user] = score;
    }

    function submitScores(ReputationScoreUpdate[] calldata updates, uint64, bytes calldata) external {
        uint256 len = updates.length;
        for (uint256 i = 0; i < len; i++) {
            ReputationScoreUpdate calldata update = updates[i];
            _liveScore[update.user] = update.score;
            nextNonce[update.user] = update.nonce + 1;
        }
    }

    function scoreOf(address user) external view returns (uint256) {
        return _liveScore[user];
    }

    function snapshotPeriodScores(uint256, uint256, uint256, address[] calldata members)
        external
        returns (bytes32 snapshotId)
    {
        snapshotId = keccak256(abi.encodePacked(address(this), block.chainid, _snapshotNonce++, block.timestamp));
        uint256 len = members.length;
        for (uint256 i = 0; i < len; i++) {
            _snapshotScore[snapshotId][members[i]] = _liveScore[members[i]];
        }
    }

    function scoreOfAt(bytes32 snapshotId, address user) external view returns (uint256) {
        return _snapshotScore[snapshotId][user];
    }
}
