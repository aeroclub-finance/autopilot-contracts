// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PermanentLocksPoolV2.sol";

interface IRootVotingRewardsFactory {
  function setRecipient(uint256 _chainid, address _recipient) external;
}

/// @title Autopilot Permanent Locks Vault V2 (Batched Individual Voting) Velodrome Edition
/// @notice A vault contract that stores individual NFTs and votes with them in batches
/// @dev This version votes with individual NFTs in batches to optimize gas while avoiding delegation requirements
/// @author Autopilot Team
contract VelodromePermanentLocksPoolV2 is PermanentLocksPoolV2 {

  /// @notice Emitted when token leaf receiver is changed
  /// @param chain_id ID of the chain for which the receiver was set
  /// @param receiver_address Address of the new receiver on the target chain
  event TokenLeafReceiverChanged(
    uint256 indexed chain_id,
    address indexed receiver_address
  );

  constructor(
    IveNFT _nft_locks_contract,
    IVoter _voter_contract,
    uint256 _epochs_offset_timestamp,
    IERC20 _rewards_token,
    IRewardsDistributor _rewards_distributor,
    IDepositValidator _deposit_validator,
    uint256 _window_preepoch_duration,
    uint256 _window_postepoch_duration
  ) PermanentLocksPoolV2(
    _nft_locks_contract,
    _voter_contract,
    _epochs_offset_timestamp,
    _rewards_token,
    _rewards_distributor,
    _deposit_validator,
    _window_preepoch_duration,
    _window_postepoch_duration
  ) { }

  /// @notice Sets the recipient address for token leaf on a specific chain
  /// @dev Only owner can call this function
  /// @param _chain_id ID of the chain for which to set the recipient
  /// @param _receiver_address Address of the recipient on the target chain
  /// @param _root_voting_rewards_factory Address of the RootVotingRewardsFactory contract
  function setTokenLeafReceiver(
    uint256 _chain_id,
    address _receiver_address,
    IRootVotingRewardsFactory _root_voting_rewards_factory
  ) external onlyOwner {
    require(_receiver_address != address(0), "ZA");
    _root_voting_rewards_factory.setRecipient(_chain_id, _receiver_address);
    emit TokenLeafReceiverChanged(_chain_id, _receiver_address);
  }
	
}