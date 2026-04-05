// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";

contract ChainoraProtocolTimelock is Events {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    struct Operation {
        uint64 readyAt;
        bool executed;
    }

    uint64 public minDelay;
    address public admin;

    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => Operation) public operations;

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Errors.Unauthorized();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!_roles[role][msg.sender]) revert Errors.Unauthorized();
        _;
    }

    constructor(
        uint64 minDelay_,
        address admin_,
        address[] memory proposers,
        address[] memory executors,
        address[] memory cancellers
    ) {
        if (admin_ == address(0)) revert Errors.ZeroAddress();

        minDelay = minDelay_;
        admin = admin_;

        uint256 len = proposers.length;
        for (uint256 i = 0; i < len; i++) {
            _roles[PROPOSER_ROLE][proposers[i]] = true;
        }

        len = executors.length;
        for (uint256 i = 0; i < len; i++) {
            _roles[EXECUTOR_ROLE][executors[i]] = true;
        }

        len = cancellers.length;
        for (uint256 i = 0; i < len; i++) {
            _roles[CANCELLER_ROLE][cancellers[i]] = true;
        }
    }

    receive() external payable {}

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        _roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        _roles[role][account] = false;
    }

    function updateDelay(uint64 newDelay) external onlyAdmin {
        uint64 oldDelay = minDelay;
        minDelay = newDelay;
        emit ChainoraTimelockDelayUpdated(oldDelay, newDelay);
    }

    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint64 delay
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32 id) {
        if (delay < minDelay) revert Errors.InvalidConfig();

        id = hashOperation(target, value, data, predecessor, salt);
        Operation storage op = operations[id];
        if (op.readyAt != 0 || op.executed) revert Errors.InvalidState();

        uint64 readyAt = uint64(block.timestamp) + delay;
        operations[id] = Operation({readyAt: readyAt, executed: false});
        emit ChainoraTimelockScheduled(id, target, value, readyAt);
    }

    function cancel(bytes32 id) external onlyRole(CANCELLER_ROLE) {
        Operation storage op = operations[id];
        if (op.readyAt == 0 || op.executed) revert Errors.InvalidState();
        delete operations[id];
        emit ChainoraTimelockCanceled(id);
    }

    function execute(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        external
        payable
        onlyRole(EXECUTOR_ROLE)
        returns (bytes memory returnData)
    {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);

        Operation storage op = operations[id];
        if (op.readyAt == 0 || op.executed) revert Errors.InvalidState();
        if (block.timestamp < op.readyAt) revert Errors.DeadlineNotReached();

        if (predecessor != bytes32(0)) {
            Operation memory prev = operations[predecessor];
            if (!prev.executed) revert Errors.InvalidState();
        }

        op.executed = true;

        (bool ok, bytes memory result) = target.call{value: value}(data);
        if (!ok) {
            op.executed = false;
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit ChainoraTimelockExecuted(id, target, value, result);
        returnData = result;
    }
}
