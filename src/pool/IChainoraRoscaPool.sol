// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Types} from "src/libraries/Types.sol";

interface IChainoraRoscaPool {
    function initialize(Types.PoolInitConfig calldata initConfig) external;

    function submitJoinRequest() external returns (uint256 requestId);

    function voteJoinRequest(uint256 requestId, bool support) external;

    function acceptJoinRequestAndLockDeposit(uint256 requestId) external;

    function cancelJoinRequest(uint256 requestId) external;

    function creator() external view returns (address);

    function poolStatus() external view returns (Types.PoolStatus);

    function contributionAmount() external view returns (uint256);

    function targetMembers() external view returns (uint16);

    function minReputation() external view returns (uint256);

    function activeMemberCount() external view returns (uint256);

    function publicRecruitment() external view returns (bool);

    function memberReputationSnapshot(address account) external view returns (uint256);

    function joinRequest(uint256 requestId)
        external
        view
        returns (address applicant, uint256 yesVotes, uint256 noVotes, bool open);
}
