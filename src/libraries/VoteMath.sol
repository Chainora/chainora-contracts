// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library VoteMath {
    function isTwoThirdsOrMore(uint256 yesVotes, uint256 totalVoters) internal pure returns (bool) {
        if (totalVoters == 0) {
            return false;
        }
        return yesVotes * 3 >= totalVoters * 2;
    }

    function isUnanimous(uint256 yesVotes, uint256 totalVoters) internal pure returns (bool) {
        if (totalVoters == 0) {
            return false;
        }
        return yesVotes == totalVoters;
    }
}
