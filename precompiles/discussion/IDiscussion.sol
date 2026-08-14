// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice Thin EVM adapter to Kudora's canonical x/discussion state.
interface IDiscussion {
    function post(uint64 proposalId, uint64 parentId, bytes calldata content) external returns (uint64 messageId);
    function react(uint64 proposalId, uint64 messageId, uint8 reaction) external returns (bool success);
    function zap(uint64 proposalId, uint64 messageId, uint256 amount) external returns (bool success);
    function authorizeSession(address session, uint64 expiresAt, uint256 fundAmount) external returns (bool success);
    function revokeSession(address session) external returns (bool success);
}
