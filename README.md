# Autopilot Protocol Security & How It Works

## What Is Autopilot?

Autopilot is a non-custodial veAERO optimization protocol that automates your voting strategy while keeping your NFTs completely secure. You maintain full ownership of your locks while our automated system handles the complex task of optimizing voting rewards.

## 🔒 Your Security: How Your Locks Are Protected

### What Makes Your NFTs Safe

**Autopilot CANNOT:**
- Transfer your NFTs to other wallets or addresses
- Modify your lock duration or amount  
- Prevent you from withdrawing your NFTs
- Access or steal other users' NFTs
- Change the core security rules of the protocol

**Autopilot CAN ONLY:**
- Vote using your NFT's voting power for optimal pools
- Collect voting rewards (bribes and fees) earned from your votes
- Collect automatic AERO distributions from the protocol
- Reset previous votes to vote again in new epochs

### Non-Custodial Design

You remain the true owner of your NFTs:
- **Individual tracking**: Your NFTs are tracked separately from all other users
- **Withdrawal rights**: You can reclaim your NFTs anytime (outside bot operation windows)
- **Proportional rewards**: You receive rewards based exactly on your voting power contribution

## 🗳️ How Our Voting Strategy Works

### Advanced Optimization Formula

Our algorithm doesn't randomly vote. It analyzes multiple factors to maximize your returns:

- **Pool Performance History**: We track which pools consistently deliver good rewards
- **Current Incentives**: How much each pool is paying in bribes for votes
- **Trading Volume & TVL**: Larger, more active pools tend to be more stable
- **Gas Efficiency**: We optimize for the best net returns after transaction costs
- **Risk Assessment**: Balancing high rewards with pool reliability

The system calculates the expected return-on-investment for each possible voting allocation and selects the combination that maximizes your rewards.

### How Voting Gets Executed

**Batch Processing Strategy:**
- Our bots vote with multiple NFTs simultaneously to save on gas costs
- Each batch is optimized to fit within blockchain transaction limits
- If individual NFTs fail, others in the batch still succeed
- Multiple backup systems ensure votes go through even during network congestion

## ⏰ The Special Window System

### When Bot Operations Happen

The protocol operates on a precise schedule to ensure fair reward distribution:

**Special Window Timing**: 
- Starts ~90 minutes before each weekly epoch ends
- Continues for ~30 minutes after the new epoch begins
- Total duration: ~2 hours per week
- Special Window Postepoch duration in practice will be less than an hour or even 30 mins, as it takes just about ~30 seconds to do all the needed bot stuff and finally snapshot.
- Snapshot itself immidietely closes the special window

**During Special Window:**
- ❌ You cannot deposit or withdraw NFTs
- ✅ Bots perform critical operations: voting, claiming rewards, swapping tokens
- ✅ System synchronizes and prepares for the next epoch

**Outside Special Window:**
- ✅ You have full access to deposit and withdraw your NFTs
- ✅ You can claim your accumulated USDC rewards anytime
- ❌ Bot operations are restricted to prevent interference

### Why Special Windows Are Necessary

This restriction prevents timing attacks and ensures fair reward calculations:
- Stops users from depositing right before rewards are distributed to dilute others
- Gives bots uninterrupted time to execute complex multi-step operations
- Maintains mathematical accuracy in reward distribution calculations

## 💰 From Chaos to USDC: How Rewards Work

### The Complete Reward Pipeline

**Step 1: Earning Rewards**
Your NFTs earn two types of rewards:
- **Voting Rewards**: Bribes and fees paid by pools for your votes
- **Rebase Rewards**: Automatic AERO distributions from the protocol

**Step 2: Collecting Everything**
After each epoch, our bots automatically:
- Claim all voting rewards from every pool you voted for
- Collect any rebase rewards your NFTs earned
- Gather dozens of different reward tokens into the main contract

**Step 3: Converting to USDC**
All reward tokens get automatically swapped to USDC because:
- **Price Stability**: No worrying about reward token volatility
- **Simplicity**: One stable token instead of managing many different tokens
- **Liquidity**: USDC is universally accepted and easy to use

**Step 4: Secure Storage & Distribution**
- Converted USDC is stored in an isolated vault contract
- Your share is calculated based on your exact voting power contribution
- You can withdraw your USDC rewards anytime, independent of your NFT deposits

### Proportional Reward Distribution

The math is simple and transparent:
```
Your Reward = (Your Voting Power ÷ Total Voting Power) × Total Rewards
```

This ensures you get exactly your fair share - no more, no less.

## 🛡️ Multiple Layers of Security

### Contract-Level Protection

**Immutable Security Rules**: The core security features cannot be changed by anyone
**Access Controls**: Even system administrators cannot access user funds
**Isolation**: Your NFTs and rewards are tracked completely separately from other users

### Mathematical Guarantees

**Precision Protection**: All calculations use high-precision math to prevent rounding errors
**Historical Integrity**: Past reward calculations cannot be modified retroactively
**Proportional Fairness**: The math guarantees you receive your exact proportional share

### Operational Safeguards

**Emergency Systems**: Built-in mechanisms keep the protocol running even if bots fail
**Gap Recovery**: System automatically handles missed epochs without losing your voting power
**Manual Override**: Community can trigger emergency functions if needed

## 🔧 Controlled Upgradeability

### What Can Be Updated

**Upgradeable Components:**
- **Reward Swapper**: Can be improved for better swap rates and lower fees
- **Deposit Rules**: Requirements for minimum lock sizes can be adjusted
- **Bot Permissions**: Authorized operators can be added or removed

**Immutable Components:**
- Your NFT ownership and withdrawal rights
- Core reward calculation mathematics
- Security access controls and restrictions
- The fundamental non-custodial architecture

### Governance Limitations

Even protocol administrators cannot:
- Access or move your NFTs
- Modify your personal reward calculations
- Change core security functions
- Override your withdrawal rights

## 🚨 Risk Management

### Smart Contract Security

**Battle-Tested Code**: Uses industry-standard security libraries
**No Custody Risk**: Your NFTs never leave your control
**Transparent Operations**: All actions are recorded on the blockchain

### Operational Resilience

**Bot Failure Protection**: System continues working even if automated bots fail
**Manual Intervention**: Emergency functions allow community intervention if needed
**Individual Recovery**: You can always withdraw your NFTs independently

### Economic Risk Mitigation

**Diversification**: Voting strategy spreads across multiple pools
**Stable Rewards**: USDC conversion eliminates token volatility
**Performance Tracking**: Continuous optimization based on actual results

## 🔍 Complete Transparency

### On-Chain Verification

Everything is publicly verifiable on the Base blockchain:
- Your NFT deposits and withdrawals
- All voting decisions and their outcomes
- Reward calculations and distributions
- Bot operations and their results

### Real-Time Monitoring

The protocol emits detailed logs for every action:
- When you deposit or withdraw NFTs
- When votes are cast with your NFTs
- When rewards are claimed and distributed
- When USDC is available for withdrawal

## Bottom Line

Autopilot provides automated veAERO optimization with bank-grade security. Your NFTs remain under your control while sophisticated algorithms maximize your rewards. The protocol is designed to be trustless - you don't need to trust us, just verify the blockchain.