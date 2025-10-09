// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IPermanentLocksPoolV1.sol";

interface IPermanentLocksPoolV2 is IPermanentLocksPoolV1 {
  /// @notice Returns the rewards token used in the locks pool
  function rewards_token() external view returns (IERC20);

  /// @notice Checks if an operator is permitted to perform actions in the locks pool
  /// @param operator Address of the operator to check
  function permitted_operators(address operator) external view returns (bool);

  /// @notice Takes a snapshot of current rewards and updates the pool state
  /// @param amount Amount of rewards to snapshot
  function snapshotRewards(uint256 amount) external;

  function epochs_offset_timestamp() external view returns (uint256);

  function last_snapshot_id() external view returns (uint256);

  function total_tracked_weight(uint256 epoch_id) external view returns (uint256);

}