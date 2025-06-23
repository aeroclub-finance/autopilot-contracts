## Expected production deployment params:

```
_nft_locks_contract: "0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4"
_voter_contract: "0x16613524e02ad97eDfeF371bC883F2F5d6C480A5"
_epochs_offset_timestamp: "1692835200"
_rewards_token: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
_rewards_distributor: "0x227f65131A261548b057215bB1D5Ab2997964C7d"
_deposit_validator: "0x0000000000000000000000000000000000000000"
_window_preepoch_duration: "5400"
_window_postepoch_duration: "1800"
```

There are 4 main contracts:

## Core Contracts
1. **`RewardsVault.sol`**: Generic token storage vault for holding rewards tokens. Automatically deployed by the PermanentLocksPool contract.
2. **`SwapperV1.sol`**: After rewards are collected, the PermanentLocksPool transfers them to the swapper, which swaps them for stablecoins (usually USDC) and sends them back to the pool. THIS CONTRACT IS REPLACEABLE - we can deploy new swapper versions and update the reference in the pool contract.
3. **`DepositValidatorV1.sol`**: Validates deposits for PermanentLocksPool contracts by checking minimum lock requirements. THIS CONTRACT IS REPLACEABLE - we can deploy new validator versions and update the reference in the pool contract.
4. **`PermanentLocksPoolV1.sol`**: Main pool contract that manages user deposits, voting, and reward distribution using batched individual voting strategy. Users deposit veNFT locks and receive proportional rewards.

## Pool Contract Versions
We have 3 versions of the permanent locks pool contract, each using different voting strategies:

3. **`PermanentLocksPoolV1.sol`**: 
   - **Voting Strategy**: Batched individual voting
   - **How it works**: Makes multiple transactions for voting, batching just a couple of locks with the same voting weights until max gas limit is reached
   - **Status**: Ready to deploy (no whitelist required)
   - **Gas cost**: Higher due to multiple transactions

4. **`PermanentLocksPoolV2.sol`**: 
   - **Voting Strategy**: Delegation to private Aerodrome Relay
   - **How it works**: Delegates all locks to a private Aerodrome Relay, allowing us to vote with just one lock in one transaction
   - **Status**: Requires Aerodrome team to whitelist us to create managed lock NFTs
   - **Gas cost**: Lowest (single transaction voting)

5. **`PermanentLocksPoolV3.sol`**: 
   - **Voting Strategy**: Merge/Split flow
   - **How it works**: Merges all deposited locks into one big lock for voting, then splits on withdrawal
   - **Status**: Requires Aerodrome team whitelist for split functionality
   - **Gas cost**: Medium (single voting transaction, but merge/split overhead)

## The Flow (applies to all pool versions):
- User deposits permanent lock NFTs into one of the PermanentLocksPool contracts
- The contract calculates the user's share based on their lock's voting power
- User can withdraw their locks any time, only outside of *Special Window*
- *Special Window* is a period when Autopilot bots perform critical actions in the pool contract, saving snapshots, etc.

## Voting Process (varies by version):
- **V1**: At ~2 hours before epoch end, the *Special Window* starts. Users depositing during this time are counted for the next epoch. The bot votes with all locks in multiple transactions, batching locks until gas limit is reached
- **V2**: Uses delegation to managed NFT - single transaction voting (requires Aerodrome whitelist)  
- **V3**: Uses merge/split flow - merges all locks into one for voting (requires Aerodrome whitelist for split)

## Reward Processing:
- After epoch end, the bot claims rewards and transfers them to `SwapperV1.sol`
- The swapper swaps rewards for stablecoins and sends them back to the pool contract
- Claim, transfer and swap are minimum 3 separate transactions
- With the swap transaction, we save a snapshot of the pool state to calculate user reward shares
- Users can withdraw their reward share any time

## Epoch Management and Emergency Synchronization System

The PermanentLocksPool contracts implement a sophisticated epoch management system that ensures accurate reward distribution and prevents reward dilution through automatic synchronization mechanisms.

### Emergency Snapshot Mechanism
- Every user function (deposit, withdraw, claim) starts with an `_emergencySnapshot()` call
- This ensures `last_snapshot_id` is ALWAYS synchronized with the current epoch before any user action
- Prevents desynchronization issues that could lead to reward calculation errors
- The emergency snapshot is automatic and transparent to users

### Per-Epoch Weight Tracking
- `total_tracked_weight[epoch_id]` stores voting power for each epoch separately
- This prevents reward dilution when users deposit after voting but before snapshot
- Each epoch has its own weight calculation, ensuring rewards are distributed only to participants who were eligible for that epoch's voting

### Special Window Logic
- During the Special Window (~2 hours before epoch end), user deposits are assigned to the NEXT epoch
- This ensures deposits during critical bot operations don't interfere with current epoch calculations
- Weight assignment logic: `if (_isInSpecialWindow(last_snapshot_id)) { deposit_weight_goes_to_next_epoch } else { deposit_weight_goes_to_current_epoch }`

### Epoch Gap Handling
- When multiple epochs are missed, the snapshot functions handle gaps intelligently
- Gap condition: `current_epoch > last_snapshot_id + 1` (gaps greater than 1 epoch)
- Gap handling: `total_tracked_weight[current_epoch] += total_tracked_weight[last_snapshot_id] + total_tracked_weight[last_snapshot_id + 1]`
- This preserves voting power across missed epochs and ensures continuous reward eligibility

### Automatic Synchronization Architecture
- The combination of emergency snapshots and per-epoch tracking creates a self-healing system
- Users cannot accidentally deposit in ways that dilute existing participants' rewards
- The system automatically handles edge cases like missed epochs or delayed bot operations
- Weight tracking ensures mathematical accuracy in all reward calculations

This architecture guarantees that:
1. Reward calculations are always mathematically correct
2. Users who participate in voting receive their fair share
3. Late deposits don't dilute rewards for existing participants
4. The system remains synchronized even if epochs are missed
5. All edge cases are handled automatically without manual intervention

## Deposit Validation System

The deposit validation system provides flexible control over which locks can be deposited into the pool, with upgradeability for changing requirements over time.

### DepositValidatorV1 Contract
- **Purpose**: Validates deposits by checking minimum lock voting power requirements
- **Upgradeability**: Similar to the swapper contract, the pool owner can deploy new validator versions and update the reference
- **Validation Method**: `validateDepositOrFail()` - uses "OrFail" pattern with internal `require()` statements
- **Current Logic**: Checks that `veNFT.balanceOfNFT(lock_id) >= minimum_lock_amount`

### Integration with Pool Contract
- Pool contract calls validator during deposit: `deposit_validator.validateDepositOrFail(nft_contract, lock_id, depositor)`
- If validator address is `address(0)`, validation is skipped (allows deposits without restrictions)
- Pool owner can update validator reference via `setDepositValidator()` function
- Validation happens before any state changes in the deposit process

### Configurable Parameters
- **minimum_lock_amount**: Owner-configurable minimum voting power required for deposits
- Can be updated via `setMinimumLockAmount()` to adjust requirements as needed
- Supports setting to 0 to allow any size locks

### Upgradeability Pattern
- New validator versions can implement different validation logic (e.g., whitelist checks, complex eligibility rules)
- Pool contract owner deploys new validator and calls `setDepositValidator(new_address)`
- Existing deposits remain unaffected by validator changes
- Provides flexibility to adapt deposit requirements without redeploying the entire pool contract
