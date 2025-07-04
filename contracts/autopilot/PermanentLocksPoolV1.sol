// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../aerodrome/IVoter.sol";
import "../aerodrome/IveNFT.sol";
import "../aerodrome/IRewardsDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RewardsVault.sol";
import "./DepositValidatorV1.sol";

/// @title Aeroclub Permanent Locks Vault V1 (Batched Individual Voting)
/// @notice A vault contract that stores individual NFTs and votes with them in batches
/// @dev This version votes with individual NFTs in batches to optimize gas while avoiding delegation requirements
/// @author Aeroclub Team
contract PermanentLocksPoolV1 {

  /// @notice The veNFT contract for managing locked positions
  IveNFT public immutable nft_locks_contract;
  
  /// @notice The voter contract for managing votes and claiming rewards
  IVoter public immutable voter_contract;
  
  /// @notice The token used for reward distribution (typically USDC)
  IERC20 public immutable rewards_token;

  /// @notice The rewards distributor contract for claiming rebase rewards
  IRewardsDistributor public immutable rewards_distributor;

  /// @notice Timestamp offset for epoch calculations (depends on Aerodrome/Velodrome)
  /// @dev This aligns our epochs with the underlying protocol's epoch system
  uint256 public immutable epochs_offset_timestamp;

  uint256 public window_preepoch_duration;

  uint256 public window_postepoch_duration;

  /// @notice Address of the auto-swapper contract that processes rewards
  /// @dev Only this address can call snapshotReward function
	address public swapper_contract_address;
  
  /// @notice Mapping of addresses authorized to perform operational tasks
  /// @dev These operators can vote, claim rewards, and transfer tokens to swapper
  mapping(address => bool) public permitted_operators;
  
  /// @notice Contract owner with administrative privileges
  address public owner;
  
  /// @notice The rewards vault contract for storing and managing user rewards
  RewardsVault public rewards_vault;

  /// @notice The deposit validator contract for validating deposits
  DepositValidatorV1 public deposit_validator;

  /// @notice Scaling factor for reward calculations to maintain precision
  uint256 public constant SCALE = 1e18;

  
  /// @notice Total tracked voting power from users who deposited through this contract per epoch
  /// @dev Used for proportional reward calculations, indexed by snapshot_id
  mapping(uint256 => uint256) public total_tracked_weight;
  
  /// @notice Accumulated scaled rewards per unit of voting power
  /// @dev This value continuously increases with each reward snapshot
  uint256 public acc_reward_scaled;
  
  /// @notice ID of the last reward snapshot (corresponds to epoch ID)
  uint256 public last_snapshot_id;

  /// @notice Mapping from lock_id to user's lock index in their userLocks array
  mapping(uint256 => uint256) public lock_id_to_user_index;


  /// @notice Whether deposits are paused
  bool public deposits_paused = true;

  /// @title Individual Lock Deposit Information Structure
  /// @notice Stores all data related to a specific lock deposit
  /// @dev This struct tracks each lock deposit separately for accurate reward calculation
  struct LockInfo {
    /// @notice Original NFT ID that was deposited (for reference)
    uint256 lock_id;
    /// @notice acc_reward_scaled value at time when THIS lock was deposited
    /// @dev Used to calculate rewards earned since this lock's deposit
    uint256 reward_scaled_start;
    /// @notice First snapshot ID that this lock is eligible for
    /// @dev This lock can only claim rewards from snapshots >= this ID
    uint256 start_snapshot_id;


    uint256 voting_power;
  }
  
  /// @notice Mapping from user address to array of their lock deposits
  mapping(address => LockInfo[]) public user_locks;

  /// @notice Mapping from lock ID to it's owner 
  mapping(uint256 => address) public lock_owner;

  // ============================================================================
  // EVENTS
  // ============================================================================

  /// @notice Emitted when a user deposits a permanent lock into the vault
  /// @param user Address of the user making the deposit
  /// @param deposited_nft_id Token ID of the deposited veNFT
  /// @param lock_index Index of this lock in user's lock array
  /// @param amount Voting power of the deposited lock
  /// @param start_snapshot_id Starting snapshot ID for this lock
  /// @param reward_scaled_start Starting reward scaled value for this lock
  event Deposit(address indexed user, uint256 indexed deposited_nft_id, uint256 lock_index, uint256 amount, uint256 start_snapshot_id, uint256 reward_scaled_start);
  
  /// @notice Emitted when a user withdraws a lock from the vault
  /// @param user Address of the user making the withdrawal
  /// @param withdrawn_nft_id Token ID of the withdrawn veNFT
  /// @param amount Voting power of the withdrawn lock
  event Withdraw(address indexed user, uint256 indexed withdrawn_nft_id, uint256 amount);
  
  /// @notice Emitted when a user claims their accumulated rewards
  /// @param user Address of the user claiming rewards
  /// @param reward_amount Amount of rewards claimed
  event Claim(address indexed user, uint256 reward_amount);
  
  /// @notice Emitted when a new reward snapshot is taken
  /// @param reward_amount Amount of rewards distributed in this snapshot
  /// @param snapshot_id ID of the snapshot (epoch ID)
  /// @param acc_reward_scaled Current accumulated reward scaled value
  event RewardsSnapshot(uint256 reward_amount, uint256 snapshot_id, uint256 acc_reward_scaled);
  
  /// @notice Emitted when the swapper contract address is updated
  /// @param old_swapper Previous swapper contract address
  /// @param new_swapper New swapper contract address
  event SwapperAddressUpdated(address indexed old_swapper, address indexed new_swapper);

  /// @notice Emitted when deposit validator contract is updated
  /// @param old_validator Previous deposit validator contract address
  /// @param new_validator New deposit validator contract address
  event DepositValidatorUpdated(address indexed old_validator, address indexed new_validator);
  
  /// @notice Emitted when operator permissions are updated
  /// @param operator Address of the operator
  /// @param permitted Whether the operator is now permitted
  event OperatorPermissionUpdated(address indexed operator, bool permitted);

  /// @notice Emitted when master NFT is created or updated
  /// @param old_nft_id Previous master NFT ID (0 if first time)
  /// @param new_nft_id New master NFT ID
  /// @param total_amount Total voting power in the new master NFT
  event MasterNftUpdated(uint256 indexed old_nft_id, uint256 indexed new_nft_id, uint256 total_amount);

  /// @notice Emitted when window durations are updated
  /// @param old_preepoch_duration Previous pre-epoch window duration
  /// @param new_preepoch_duration New pre-epoch window duration
  /// @param old_postepoch_duration Previous post-epoch window duration
  /// @param new_postepoch_duration New post-epoch window duration
  event WindowDurationsUpdated(
    uint256 old_preepoch_duration,
    uint256 new_preepoch_duration,
    uint256 old_postepoch_duration,
    uint256 new_postepoch_duration
  );

  event EmergencySnapshot(uint256 snapshot_id);

  /// @notice Emitted when ownership is transferred
  /// @param previous_owner Address of the previous owner
  /// @param new_owner Address of the new owner
  event OwnershipTransferred(address indexed previous_owner, address indexed new_owner);

  /// @notice Emitted when deposits are paused or resumed
  /// @param paused Whether deposits are now paused
  event DepositsPausedUpdated(bool paused);

  /// @notice Emitted when voting is completed
  /// @param nft_ids Array of NFT IDs that voted
  event VotingCompleted(uint256[] nft_ids);

  /// @notice Emitted when voting rewards are claimed
  /// @param nft_ids Array of NFT IDs that claimed rewards
  event VotingRewardsClaimed(uint256[] nft_ids);

  /// @notice Emitted when rebase rewards are claimed
  /// @param nft_ids Array of NFT IDs that claimed rebase rewards
  /// @param final_balances Array of final balances for each NFT
  event RebaseRewardsClaimed(uint256[] nft_ids, uint256[] final_balances);

  /// @notice Emitted when tokens are transferred to swapper
  /// @param tokens Array of token addresses transferred
  event SwapperFilled(address[] tokens);

  // ============================================================================
  // MODIFIERS
  // ============================================================================

  /// @notice Restricts access to contract owner only
  modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
  }

  /// @notice Restricts access to permitted operators only
  modifier onlyPermittedOperator() {
    require(permitted_operators[msg.sender], "Not permitted operator");
    _;
  }

  /// @notice Restricts access to swapper contract only
  modifier onlySwapper() {
    require(swapper_contract_address == msg.sender, "Not a swapper contract");
    _;
  }


  // ============================================================================
  // CONSTRUCTOR
  // ============================================================================

  /// @notice Initializes the vault with required contract addresses
  /// @param _nft_locks_contract Address of the veNFT contract
  /// @param _voter_contract Address of the voter contract
  /// @param _epochs_offset_timestamp Timestamp offset for epoch calculations
  /// @param _rewards_token Address of the rewards token (typically USDC)
  /// @param _rewards_distributor Address of the rewards distributor contract
  /// @param _deposit_validator Address of the deposit validator contract (can be zero to disable)
  constructor(
    IveNFT _nft_locks_contract,
    IVoter _voter_contract,
    uint256 _epochs_offset_timestamp,
    IERC20 _rewards_token,
    IRewardsDistributor _rewards_distributor,
    DepositValidatorV1 _deposit_validator,
    uint256 _window_preepoch_duration,
    uint256 _window_postepoch_duration
  ) {
    nft_locks_contract = _nft_locks_contract;
    voter_contract = _voter_contract;
    epochs_offset_timestamp = _epochs_offset_timestamp;
    rewards_token = _rewards_token;
    rewards_distributor = _rewards_distributor;
    deposit_validator = _deposit_validator;
    owner = msg.sender;

    // V1 doesn't use managed NFTs - just stores individual NFTs

    _setWindowDurations(_window_preepoch_duration, _window_postepoch_duration);
    // _setWindowDurations requires deposits_paused to be true so we reset it here
    deposits_paused = false;
    
    // Deploy rewards vault with this contract as the authorized caller
    rewards_vault = new RewardsVault();
  }

  // ============================================================================
  // USER FUNCTIONS
  // ============================================================================

  /// @notice Deposits a veNFT lock into the vault
  /// @dev Lock must not have voted in current epoch and user must own the NFT
  /// @param _lock_id Token ID of the permanent veNFT to deposit
  function deposit(uint256 _lock_id) external {
    require(!deposits_paused, "Deposits are paused");

    _emergencySnapshot();

    IveNFT.LockedBalance memory lock = nft_locks_contract.locked(_lock_id);
    uint256 current_epoch_id = _getCurrentEpochId();

    uint256 last_voted = voter_contract.lastVoted(_lock_id);
    require(
      last_voted == 0 ||
      last_voted < epochs_offset_timestamp ||
      _getEpochIdByTimestamp(last_voted) != current_epoch_id, 
      "Already voted in current epoch"
    );

    require(
      nft_locks_contract.ownerOf(_lock_id) == msg.sender,
      "Not owner of NFT"
    );

    // Validate deposit using deposit validator contract
    if (address(deposit_validator) != address(0)) {
      deposit_validator.validateDepositOrFail(
        nft_locks_contract,
        _lock_id,
        msg.sender
      );
    }

    if(nft_locks_contract.voted(_lock_id)) {
      voter_contract.reset(_lock_id);
    }

    if(!lock.isPermanent) {
      nft_locks_contract.lockPermanent(_lock_id);
    }

    uint256 amount = nft_locks_contract.balanceOfNFT(_lock_id);
    require(amount > 0, "Zero voting power");

    nft_locks_contract.transferFrom(msg.sender, address(this), _lock_id);
    
    uint256 eligible_epoch = _isInSpecialWindow(last_snapshot_id) ? last_snapshot_id + 1 : last_snapshot_id;
    total_tracked_weight[eligible_epoch] += amount;

    LockInfo memory new_lock = LockInfo({
      lock_id: _lock_id,
      reward_scaled_start: acc_reward_scaled,
      start_snapshot_id: eligible_epoch,
      voting_power: amount
    });

    lock_owner[_lock_id] = msg.sender;
    user_locks[msg.sender].push(new_lock);

    uint256 new_lock_index = user_locks[msg.sender].length - 1;
    lock_id_to_user_index[_lock_id] = new_lock_index;

    emit Deposit(msg.sender, _lock_id, new_lock_index, amount, eligible_epoch, acc_reward_scaled);
  }

  /// @notice Withdraws a specific lock by lock ID
  /// @dev Must not be in special window and user must own the lock
  /// @param _lock_id Lock ID of the NFT to withdraw
  function withdraw(uint256 _lock_id) external {

    _emergencySnapshot();

		_isNotInSpecialWindowOrFail(last_snapshot_id);
    
    // Claim rewards before withdrawing
    _claim(_lock_id);
    
    uint256 lock_index = _getLockIndexOrFail(msg.sender, _lock_id);
    
    LockInfo storage lock_info = user_locks[msg.sender][lock_index];
    
    uint256 amount = lock_info.voting_power;
    if(lock_info.start_snapshot_id > last_snapshot_id) {
      total_tracked_weight[lock_info.start_snapshot_id] -= amount;
    } else {
      total_tracked_weight[last_snapshot_id] -= amount;
    }
    
    uint256 last_index = user_locks[msg.sender].length - 1;
    if (lock_index != last_index) {
      user_locks[msg.sender][lock_index] = user_locks[msg.sender][last_index];
      // Update mapping for the moved lock
      uint256 moved_lock_id = user_locks[msg.sender][lock_index].lock_id;
      lock_id_to_user_index[moved_lock_id] = lock_index;
    }
    user_locks[msg.sender].pop();
    
    // Clear mappings for withdrawn lock
    delete lock_owner[_lock_id];
    delete lock_id_to_user_index[_lock_id];

    nft_locks_contract.transferFrom(address(this), msg.sender, _lock_id);

    emit Withdraw(msg.sender, _lock_id, amount);
  }

  /// @notice Claims accumulated rewards for a specific lock
  /// @dev User must have lock deposited and lock ID must be valid
  /// @param _lock_id Lock ID to claim rewards from
  function claim(uint256 _lock_id) external {
    _emergencySnapshot();
    _claim(_lock_id);
  }

  /// @notice Executes multiple function calls in a single transaction
  /// @dev Allows batching of operations like multiple claims or withdrawals
  /// @param _calls Array of encoded function calls to execute
  /// @return results Array of return data from each call
  function multicall(bytes[] calldata _calls) external returns (bytes[] memory results) {
    results = new bytes[](_calls.length);
    for (uint256 i = 0; i < _calls.length; i++) {
      (bool success, bytes memory result) = address(this).delegatecall(_calls[i]);
      require(success, "Multicall: call failed");
      results[i] = result;
    }
  }

  // ============================================================================
  // OPERATOR FUNCTIONS
  // ============================================================================

  /// @notice Votes with multiple NFTs in batches during special window
  /// @dev Only permitted operators can call this during special window
  /// @param _nft_ids Array of NFT IDs to vote with
  /// @param _pools Array of pool addresses to vote for
  /// @param _percentages Array of vote weight percentages for each pool
  /// @param _for_epoch_id The epoch ID for which the vote is being cast
  function voteWithNfts(
    uint256[] calldata _nft_ids,
		address[] calldata _pools,
    uint256[] calldata _percentages,
    uint256 _for_epoch_id
  ) external onlyPermittedOperator {

		_isInSpecialWindowOrFail(last_snapshot_id);

    uint256 current_epoch_id = _getCurrentEpochId();
    require(current_epoch_id == _for_epoch_id, "Invalid epoch ID for voting");

    require(_nft_ids.length > 0, "No NFT IDs provided");
    
    for (uint256 i = 0; i < _nft_ids.length; i++) {
      uint256 nft_id = _nft_ids[i];
      require(nft_locks_contract.ownerOf(nft_id) == address(this), "Contract doesn't own NFT");
      
      if (nft_locks_contract.voted(nft_id)) {
        voter_contract.reset(nft_id);
      }
      
      voter_contract.vote(nft_id, _pools, _percentages);
    }

    emit VotingCompleted(_nft_ids);
  }

  /// @notice Claims voting rewards (bribes) from gauges for multiple NFTs
  /// @dev Only permitted operators can call this during special window
  /// @param _nft_ids Array of NFT IDs to claim rewards for
  /// @param _bribes_and_fees Array of bribe/fee contract addresses
  /// @param _tokens Array of token arrays for each bribe contract
  function claimVotingRewards(
    uint256[] calldata _nft_ids,
    address[] calldata _bribes_and_fees,
		address[][] calldata _tokens
  ) external onlyPermittedOperator {

		_isInSpecialWindowOrFail(last_snapshot_id);

    require(_bribes_and_fees.length == _tokens.length, "Array length mismatch");
    require(_nft_ids.length > 0, "No NFT IDs provided");

    // Claim rewards for each NFT
    for (uint256 i = 0; i < _nft_ids.length; i++) {
      uint256 nft_id = _nft_ids[i];
      require(nft_locks_contract.ownerOf(nft_id) == address(this), "Contract doesn't own NFT");
      
      voter_contract.claimBribes(
        _bribes_and_fees,
        _tokens,
        nft_id
      );
    }

    emit VotingRewardsClaimed(_nft_ids);
  }

  /// @notice Claims rebase rewards from RewardsDistributor for multiple NFTs
  /// @dev Only permitted operators can call this outside special window
  ///      This claims rebase rewards that are automatically added to each NFT
  /// @param _nft_ids Array of NFT IDs to claim rebase rewards for
  function claimRebaseRewards(
    uint256[] calldata _nft_ids
  ) external onlyPermittedOperator {

    _emergencySnapshot();

    _isNotInSpecialWindowOrFail(last_snapshot_id);

    require(_nft_ids.length > 0, "No NFT IDs provided");
    
    uint256 total_before_balance = 0;
    uint256 total_after_balance = 0;

    // Claim rebase rewards for each NFT
    uint256[] memory final_balances = new uint256[](_nft_ids.length);
    for (uint256 i = 0; i < _nft_ids.length; i++) {

      uint256 nft_id = _nft_ids[i];
      address nft_owner = lock_owner[nft_id];
      uint256 nft_index = lock_id_to_user_index[nft_id];

      LockInfo storage lock_info = user_locks[nft_owner][nft_index];

      require(nft_owner != address(0), "NFT not in vault");

      total_before_balance += lock_info.voting_power;

      rewards_distributor.claim(nft_id);

      // now we have updated balance for this NFT
      
      uint256 new_lock_balance = nft_locks_contract.balanceOfNFT(nft_id);
      total_after_balance += new_lock_balance;
      
      lock_info.voting_power = new_lock_balance;
      final_balances[i] = new_lock_balance;
    }

    // Apply rebase change (can be positive or negative)
    if (total_before_balance > 0 && total_after_balance != total_before_balance) {
      int256 rebase_change = int256(total_after_balance) - int256(total_before_balance);
      int256 new_weight = int256(total_tracked_weight[last_snapshot_id]) + rebase_change;

      // we need to care only about last_snapshot_id because we 
      // cannot have total_tracked_weight[last_snapshot_id + 1]
      // outside of special window
      total_tracked_weight[last_snapshot_id] = new_weight > 0 ? uint256(new_weight) : 0;
    }

    emit RebaseRewardsClaimed(_nft_ids, final_balances);
  }

  /// @notice Transfers accumulated reward tokens to the swapper contract
  /// @dev Only permitted operators can call this during special window
  ///      This prepares tokens for swapping to the reward token (USDC)
  /// @param _tokens Array of token addresses to transfer
  function fillSwapper(
		address[] calldata _tokens
  ) external onlyPermittedOperator {

		_isInSpecialWindowOrFail(last_snapshot_id);

    require(swapper_contract_address != address(0), "Swapper contract not set");

    for (uint256 i = 0; i < _tokens.length; i++) {

      IERC20 token = IERC20(_tokens[i]);
      uint256 balance = token.balanceOf(address(this));
      if (balance > 0) {
        SafeERC20.safeTransfer(token, swapper_contract_address, balance);
      }
    }

    emit SwapperFilled(_tokens);
  }

  // ============================================================================
  // SWAPPER FUNCTIONS
  // ============================================================================

  /// @notice Creates a reward snapshot and distributes rewards proportionally
  /// @dev Only the swapper contract can call this function
  ///      This is the core function that enables reward distribution
  ///      If reward_amount is 0 or no deposits exist, only updates snapshot ID
  /// @dev Requirements:
  ///      - Cannot snapshot same epoch twice (must be new epoch)
  ///      - If reward_amount > 0, requires active deposits (total_amount > 0)
  /// @param reward_amount Amount of rewards to distribute (in reward token)
  ///        Can be 0 if no rewards were generated this epoch
  function snapshotRewards(uint256 reward_amount) external onlySwapper {

    uint256 current_epoch = _getCurrentEpochId();

    require(
      current_epoch > last_snapshot_id,
      "Already snapshoted this epoch"
    );

    if(reward_amount > 0) {

      // Transfer rewards from swapper to rewards vault
      SafeERC20.safeTransferFrom(
        rewards_token,
        swapper_contract_address,
        address(this),
        reward_amount
      );
      
      // Approve rewards vault to take the tokens
      SafeERC20.forceApprove(rewards_token, address(rewards_vault), reward_amount);
      
      // Deposit rewards into vault
      rewards_vault.deposit(rewards_token, reward_amount);

      if(total_tracked_weight[last_snapshot_id] > 0) {
        // Calculate coefficient: reward_scaled = reward_amount / total_tracked_weight
        uint256 reward_scaled = (reward_amount * SCALE) / total_tracked_weight[last_snapshot_id];

        // Increase accumulator
        acc_reward_scaled += reward_scaled;
      }
    }

    if(current_epoch > last_snapshot_id + 1) {
      total_tracked_weight[current_epoch] += total_tracked_weight[last_snapshot_id] + total_tracked_weight[last_snapshot_id + 1];
    } else {
      // Copy previous epoch's total tracked weight to new epoch
      total_tracked_weight[current_epoch] += total_tracked_weight[last_snapshot_id];
    }
    
    // Update snapshot ID to current epoch
    last_snapshot_id = current_epoch;

    emit RewardsSnapshot(reward_amount, last_snapshot_id, acc_reward_scaled);
  }

  /// @notice Internal emergency snapshot mechanism to prevent reward calculation issues
  /// @dev Automatically creates a snapshot with 0 rewards if bots fail to snapshot during special window
  ///      This ensures epoch progression continues even if automated systems fail
  /// @dev Conditions for emergency snapshot:
  ///      - Must not be in special window (prevents interference with bot operations)
  ///      - Current epoch must be different from last snapshot epoch
  /// @return success True if emergency snapshot was taken, false if conditions not met
  function _emergencySnapshot() internal returns (bool success) {

    uint256 current_epoch = _getCurrentEpochId();

    if(
      _isNotInSpecialWindow(last_snapshot_id) &&
      current_epoch > last_snapshot_id
    ) {

      // if bots somehow failed to snapshot several or more epochs
      if(current_epoch > last_snapshot_id + 1) {
        total_tracked_weight[current_epoch] += total_tracked_weight[last_snapshot_id] + total_tracked_weight[last_snapshot_id + 1];
      } else {
        // Copy previous epoch's total tracked weight to new epoch
        total_tracked_weight[current_epoch] += total_tracked_weight[last_snapshot_id];
      }

      last_snapshot_id = current_epoch;
      emit RewardsSnapshot(0, last_snapshot_id, acc_reward_scaled);
      emit EmergencySnapshot(last_snapshot_id);
      return true;
    } else {
      return false;
    }
    
  }

  /// @notice Public emergency snapshot function for manual intervention
  /// @dev Allows anyone to trigger emergency snapshot if bots fail to operate
  ///      Useful as a safety mechanism to ensure system continues functioning
  /// @dev Requirements:
  ///      - Emergency snapshot conditions must be met (see _emergencySnapshot)
  ///      - Will revert if no emergency snapshot is needed
  function emergencySnapshot() external {
    require(_emergencySnapshot(), "No emergency snapshot taken");
  }

  // ============================================================================
  // OWNER FUNCTIONS
  // ============================================================================

  /// @notice Sets the swapper contract address
  /// @dev Only owner can call this function
  /// @param _swapper_contract Address of the new swapper contract
  function setSwapperContract(address _swapper_contract) external onlyOwner {
    require(_swapper_contract != address(0), "Swapper address cannot be zero");
    address old_swapper = swapper_contract_address;
    swapper_contract_address = _swapper_contract;
    emit SwapperAddressUpdated(old_swapper, _swapper_contract);
  }

  /// @notice Updates operator permissions
  /// @dev Only owner can call this function
  /// @param _operator Address of the operator
  /// @param _permitted Whether to grant or revoke permissions
  function setPermittedOperator(address _operator, bool _permitted) external onlyOwner {
    require(_operator != address(0), "Operator address cannot be zero");
    permitted_operators[_operator] = _permitted;
    emit OperatorPermissionUpdated(_operator, _permitted);
  }

  /// @notice Transfers ownership to a new address
  /// @dev Only owner can call this function
  /// @param _new_owner Address of the new owner
  function transferOwnership(address _new_owner) external onlyOwner {
    require(_new_owner != address(0), "New owner address cannot be zero");
    address old_owner = owner;
    owner = _new_owner;
    emit OwnershipTransferred(old_owner, _new_owner);
  }

  /// @notice Updates the special window durations
  /// @dev Only owner can call this function
  /// @dev Requirements:
  ///      - Deposits must be paused
  ///      - Pre-epoch duration must be at least 90 minutes
  ///      - Post-epoch duration must be at least 30 minutes
  ///      - Combined durations must be less than 6 days to prevent overlapping windows
  /// @param _window_preepoch_duration New duration for pre-epoch window (in seconds)
  /// @param _window_postepoch_duration New duration for post-epoch window (in seconds)
  function setWindowDurations(
    uint256 _window_preepoch_duration,
    uint256 _window_postepoch_duration
  ) external onlyOwner {
    uint256 old_preepoch = window_preepoch_duration;
    uint256 old_postepoch = window_postepoch_duration;

    _setWindowDurations(_window_preepoch_duration, _window_postepoch_duration);

    emit WindowDurationsUpdated(
      old_preepoch,
      _window_preepoch_duration,
      old_postepoch,
      _window_postepoch_duration
    );
  }

  /// @notice Emergency withdrawal of unaccounted tokens from rewards vault
  /// @dev Only owner can call this function, not during special window
  /// @dev Withdraws only the difference between actual balance and tracked amount
  /// @param _token Address of the token to withdraw unaccounted amount
  /// @param _recipient Address to receive the withdrawn tokens
  /// @return withdrawn_amount Amount of unaccounted tokens withdrawn
  function emergencyWithdrawFromRewardsVault(
    IERC20 _token,
    address _recipient
  ) external onlyOwner returns (uint256 withdrawn_amount) {
    _isNotInSpecialWindowOrFail(last_snapshot_id);
    require(_recipient != address(0), "Recipient cannot be zero address");
    
    withdrawn_amount = rewards_vault.withdrawNonAccounted(_token, _recipient);
  }

  /// @notice Emergency withdrawal of non-reward tokens from this contract
  /// @dev Only owner can call this function, not during special window
  /// @param _token Address of the token to withdraw (cannot be rewards token)
  /// @param _recipient Address to receive the withdrawn tokens
  /// @param _amount Amount of tokens to withdraw
  function emergencyWithdrawFromLocksVault(
    IERC20 _token,
    address _recipient,
    uint256 _amount
  ) external onlyOwner {
    _isNotInSpecialWindowOrFail(last_snapshot_id);
    require(_recipient != address(0), "Recipient cannot be zero address");
    require(_amount > 0, "Amount must be greater than zero");
    
    SafeERC20.safeTransfer(_token, _recipient, _amount);
  }

  /// @notice Pauses or resumes deposits
  /// @dev Only owner can call this function
  /// @param _paused Whether to pause deposits
  function setDepositsPaused(bool _paused) external onlyOwner {
    deposits_paused = _paused;
    emit DepositsPausedUpdated(_paused);
  }

  /// @notice Sets the deposit validator contract address
  /// @dev Only owner can call this function
  /// @param _deposit_validator Address of the new deposit validator contract (can be zero to disable)
  function setDepositValidator(DepositValidatorV1 _deposit_validator) external onlyOwner {
    address old_validator = address(deposit_validator);
    deposit_validator = _deposit_validator;
    emit DepositValidatorUpdated(old_validator, address(_deposit_validator));
  }

  // ============================================================================
  // VIEW FUNCTIONS
  // ============================================================================

  /// @notice Retrieves lock information for a user with pagination
  /// @param _user Address of the user
  /// @param _offset Starting index for pagination
  /// @param _limit Maximum number of locks to return
  /// @return Array of LockInfo structs containing user's lock details
  function getUserLocks(address _user, uint256 _offset, uint256 _limit) external view returns (LockInfo[] memory) {
    uint256 total_locks = user_locks[_user].length;
    
    if (_offset >= total_locks) {
      return new LockInfo[](0);
    }
    
    uint256 end = _offset + _limit;
    if (end > total_locks) {
      end = total_locks;
    }
    
    uint256 length = end - _offset;
    LockInfo[] memory result = new LockInfo[](length);
    
    for (uint256 i = 0; i < length; i++) {
      result[i] = user_locks[_user][_offset + i];
    }
    
    return result;
  }
  
  /// @notice Retrieves specific lock information by lock ID and owner
  /// @param _owner Address of the lock owner
  /// @param _lock_id Lock ID to retrieve information for
  /// @return LockInfo struct containing the specific lock details
  function getUserLock(address _owner, uint256 _lock_id) external view returns (LockInfo memory) {
    uint256 lock_index = _getLockIndexOrFail(_owner, _lock_id);
    return user_locks[_owner][lock_index];
  }

  /// @notice Calculates pending rewards for a specific lock
  /// @dev This is useful for frontend display and user decision making
  /// @param _owner Address of the lock owner
  /// @param _lock_id Lock ID to calculate pending rewards for
  /// @return pending_rewards Amount of pending rewards for this lock
  function getPendingRewards(address _owner, uint256 _lock_id) external view returns (uint256 pending_rewards) {
    uint256 lock_index = _getLockIndexOrFail(_owner, _lock_id);
    LockInfo storage lock_info = user_locks[_owner][lock_index];
    
    // Return 0 if lock hasn't reached its start snapshot yet
    if (last_snapshot_id <= lock_info.start_snapshot_id) {
        return 0;
    }
    
    uint256 lock_weight = lock_info.voting_power;
    uint256 delta_acc = acc_reward_scaled - lock_info.reward_scaled_start;
    pending_rewards = (lock_weight * delta_acc) / SCALE;
  }


  /// @notice Gets total tracked weight information for current epoch
  /// @return total_tracked_weight_ Total tracked weight from users who deposited through this contract
  function getPoolInfo() external view returns (
    uint256 total_tracked_weight_
  ) {
    total_tracked_weight_ = total_tracked_weight[last_snapshot_id];
  }

  /// @notice Gets the current epoch ID
  /// @return Current epoch ID based on block timestamp
  function getCurrentEpochId() external view returns (uint256) {
    return _getCurrentEpochId();
  }


  /// @notice Provides comprehensive epoch information
  /// @dev Useful for understanding epoch timing and special window status
  /// @param _epoch_id The epoch ID to get information for
  /// @return epoch_start Timestamp when epoch starts
  /// @return epoch_end Timestamp when epoch ends
  /// @return wrapped_start Timestamp when special window starts
  /// @return wrapped_end Timestamp when special window ends
  function getEpochInfo(uint256 _epoch_id) external view returns (
    uint256 epoch_start,
    uint256 epoch_end,
    uint256 wrapped_start,
    uint256 wrapped_end
  ) {
    epoch_start = _getEpochStartAt(_epoch_id);
    epoch_end = _getEpochEndAt(_epoch_id);
    wrapped_start = _getWrappedEpochStartAt(_epoch_id);
    wrapped_end = _getWrappedEpochEndAt(_epoch_id);
  }

  // ============================================================================
  // INTERNAL FUNCTIONS
  // ============================================================================

  /// @notice Internal function to get lock index and validate owner
  /// @param _owner Address of the lock owner
  /// @param _lock_id Lock ID to get index for
  /// @return lock_index Index of the lock in owner's array
  function _getLockIndexOrFail(address _owner, uint256 _lock_id) internal view returns (uint256 lock_index) {
    lock_index = lock_id_to_user_index[_lock_id];
    require(
      lock_index < user_locks[_owner].length && user_locks[_owner][lock_index].lock_id == _lock_id,
      "Lock not found or not owned by specified owner"
    );
  }

  /// @notice Internal function to claim rewards for a specific lock
  /// @param _lock_id Lock ID to claim rewards from
  function _claim(uint256 _lock_id) internal {
    uint256 lock_index = _getLockIndexOrFail(msg.sender, _lock_id);
    LockInfo storage lock_info = user_locks[msg.sender][lock_index];
    
    if(last_snapshot_id <= lock_info.start_snapshot_id) {
      return; // Skip locks that are not eligible for rewards yet
    }
    
    uint256 lock_weight = lock_info.voting_power;
    if(lock_weight == 0) {
      return; // Skip locks with zero voting power
    }
    
    // Calculate rewards for this lock based on its proportional weight
    uint256 delta_acc = acc_reward_scaled - lock_info.reward_scaled_start;
    if (delta_acc > 0) {
      uint256 lock_payout = (lock_weight * delta_acc) / SCALE;
      
      // Update this lock's reward baseline
      lock_info.reward_scaled_start = acc_reward_scaled;
      
      if(lock_payout > 0) {
        rewards_vault.withdraw(rewards_token, msg.sender, lock_payout);
        emit Claim(msg.sender, lock_payout);
      }
    }
  }

  /// @notice Requires that current time is within special window
  /// @dev Special window is when Aeroclub bots perform critical operations
  /// @param current_epoch_id The epoch ID to check against
	function _isInSpecialWindowOrFail(
		uint256 current_epoch_id
	) internal view {
		require(
			_isInSpecialWindow(current_epoch_id),
			"Not in special window"
		);
	}

  /// @notice Checks if current time is within special window
  /// @dev Special window: 2 hours before epoch end to 1 hour after epoch start
  /// @param epoch_id The epoch ID to check against
  /// @return true if currently in special window
  function _isInSpecialWindow(
    uint256 epoch_id
  ) internal view returns (bool) {
    return (
      _getWrappedEpochEndAt(epoch_id) < block.timestamp &&
      block.timestamp <= _getWrappedEpochStartAt(epoch_id + 1)
    );
  }

  /// @notice Checks if current timestamp is NOT in special window
  /// @dev Convenience function for readable code - opposite of _isInSpecialWindow
  /// @param epoch_id The epoch ID to check the special window against
  /// @return false if currently in special window, true otherwise
  function _isNotInSpecialWindow(
    uint256 epoch_id
  ) internal view returns (bool) {
    return !_isInSpecialWindow(epoch_id);
  }

  /// @notice Requires that current time is NOT within special window
  /// @dev Used to prevent user actions during bot operation periods
  ///      Special window is when Aeroclub bots perform critical operations like:
  ///      - Voting with the master NFT
  ///      - Claiming rewards from gauges
  ///      - Transferring tokens to swapper
  /// @param epoch_id The epoch ID to check against
  function _isNotInSpecialWindowOrFail(
		uint256 epoch_id
	) internal view {
		require(
			!_isInSpecialWindow(epoch_id),
			"Currently in special window"
		);
	}

  /// @notice Converts timestamp to epoch ID
  /// @dev Epochs are weekly periods starting from epochs_offset_timestamp
  ///      Formula: (timestamp - offset) / 1 week
  ///      This aligns with Aerodrome/Velodrome epoch system
  /// @param _timestamp The timestamp to convert (must be >= epochs_offset_timestamp)
  /// @return Epoch ID for the given timestamp (0-based indexing)
  function _getEpochIdByTimestamp(
    uint256 _timestamp
  ) internal view returns (uint256) {
    return (_timestamp - epochs_offset_timestamp) / 1 weeks;
  }

	/// @notice Gets current epoch ID based on block timestamp
	/// @dev Convenience function that applies _getEpochIdByTimestamp to current time
	/// @return Current epoch ID (0-based, increments weekly)
	function _getCurrentEpochId() internal view returns (uint256) {
		return _getEpochIdByTimestamp(block.timestamp);
	}

	/// @notice Calculates the start timestamp of an epoch
	/// @dev Formula: epochs_offset_timestamp + (epoch_id * 1 week)
	///      Each epoch starts exactly at the beginning of its week
	/// @param _epoch_id The epoch ID (0-based)
	/// @return Timestamp when the epoch starts (inclusive)
	function _getEpochStartAt(
		uint256 _epoch_id
	) internal view returns (uint256) {
    return epochs_offset_timestamp + (_epoch_id * 1 weeks);
	}

	/// @notice Calculates the end timestamp of an epoch
	/// @dev Formula: epoch_start + 1 week - 1 second
	///      Ends at the last second before next epoch starts
	/// @param _epoch_id The epoch ID (0-based)
	/// @return Timestamp when the epoch ends (inclusive - last second of the week)
	function _getEpochEndAt(
		uint256 _epoch_id
	) internal view returns (uint256) {
		return _getEpochStartAt(_epoch_id) + 1 weeks - 1;
	}

	/// @notice Calculates when special window starts for an epoch
	/// @dev Special window starts 1 hour after epoch start
	///      This gives time for any epoch transition processes to complete
	///      Formula: epoch_start + 1 hour
	/// @param _epoch_id The epoch ID (0-based)
	/// @return Timestamp when special window starts for bot operations
	function _getWrappedEpochStartAt(
		uint256 _epoch_id
	) internal view returns (uint256) {
		return _getEpochStartAt(_epoch_id) + window_postepoch_duration;
	}

	/// @notice Calculates when special window ends for an epoch
	/// @dev Special window ends 2 hours before epoch end
	///      This ensures bots have completed all operations before epoch transition
	///      Formula: epoch_end - 2 hours
	/// @param _epoch_id The epoch ID (0-based)
	/// @return Timestamp when special window ends (bot operations must be complete)
	function _getWrappedEpochEndAt(
		uint256 _epoch_id
	) internal view returns (uint256) {
		return _getEpochEndAt(_epoch_id) - window_preepoch_duration;
	}

  /// @notice Internal setter for window durations with comprehensive validation
  /// @dev Validates and sets both window duration parameters
  /// @param _window_preepoch_duration Pre-epoch window duration to set
  /// @param _window_postepoch_duration Post-epoch window duration to set
  function _setWindowDurations(
    uint256 _window_preepoch_duration,
    uint256 _window_postepoch_duration
  ) internal {

    require(deposits_paused, "Cannot set window durations while deposits are active");
    require(_window_preepoch_duration >= 1.5 hours, "Pre-epoch window must be at least 90 minutes");
    require(_window_postepoch_duration >= 0.5 hours, "Post-epoch window must be at least 30 minutes");
    require(
      _window_preepoch_duration + _window_postepoch_duration < 6 days,
      "Combined window durations must be less than 6 days"
    );

    window_preepoch_duration = _window_preepoch_duration;
    window_postepoch_duration = _window_postepoch_duration;
  }
	
}