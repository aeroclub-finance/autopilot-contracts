// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Autopilot Rewards Vault
/// @notice Generic token storage vault for the PermanentLocksPool contract
/// @dev This contract holds tokens and allows only the deploying contract to deposit/withdraw
/// @author Aeroclub Team
contract RewardsVault {

	/// @notice The contract that deployed this vault
	/// @dev Only this contract can deposit/withdraw tokens
	address public immutable locks_vault_contract;


	/// @notice Mapping to track total amount of each token stored in the vault
	mapping(address => uint256) public total_tokens_stored;

	// ============================================================================
	// EVENTS
	// ============================================================================

	/// @notice Emitted when tokens are deposited into the vault
	/// @param token Address of the token deposited
	/// @param amount Amount of tokens deposited
	/// @param new_total New total amount stored after deposit
	event TokensDeposited(address indexed token, uint256 amount, uint256 new_total);

	/// @notice Emitted when tokens are withdrawn from the vault
	/// @param token Address of the token withdrawn
	/// @param recipient Address receiving the tokens
	/// @param amount Amount of tokens withdrawn
	/// @param new_total New total amount stored after withdrawal
	event TokensWithdrawn(address indexed token, address indexed recipient, uint256 amount, uint256 new_total);

	/// @notice Emitted when non-accounted (excess) tokens are withdrawn
	/// @param token Address of the token withdrawn
	/// @param recipient Address receiving the tokens
	/// @param amount Amount of excess tokens withdrawn
	event NonAccountedTokensWithdrawn(address indexed token, address indexed recipient, uint256 amount);


	// ============================================================================
	// MODIFIERS
	// ============================================================================


	/// @notice Restricts access to locks vault contract only
	modifier onlyLocksVault() {
		require(msg.sender == address(locks_vault_contract), "Not locks vault contract");
		_;
	}

	// ============================================================================
	// CONSTRUCTOR
	// ============================================================================

	/// @notice Initializes the rewards vault
	constructor() {
		locks_vault_contract = msg.sender;
	}

	// ============================================================================
	// VAULT FUNCTIONS
	// ============================================================================

	/// @notice Deposits tokens into the vault
	/// @dev Only callable by the locks vault contract
	/// @param token Address of the token to deposit
	/// @param amount Amount of tokens to deposit
	function deposit(IERC20 token, uint256 amount) external onlyLocksVault {
		require(amount > 0, "Cannot deposit zero amount");
		require(address(token) != address(0), "Cannot deposit zero address token");

		// Transfer tokens from locks vault contract to this contract
		SafeERC20.safeTransferFrom(
			token,
			locks_vault_contract,
			address(this),
			amount
		);

		// Update stored amount
		total_tokens_stored[address(token)] += amount;

		emit TokensDeposited(address(token), amount, total_tokens_stored[address(token)]);
	}

	/// @notice Withdraws tokens from the vault
	/// @dev Only callable by the locks vault contract
	/// @param token Address of the token to withdraw
	/// @param recipient Address to receive the tokens
	/// @param amount Amount of tokens to withdraw
	function withdraw(IERC20 token, address recipient, uint256 amount) external onlyLocksVault {
		require(amount > 0, "Cannot withdraw zero amount");
		require(recipient != address(0), "Cannot withdraw to zero address");
		require(address(token) != address(0), "Cannot withdraw zero address token");

		// Cap withdrawal amount to what's actually available
		uint256 available_amount = total_tokens_stored[address(token)];
		uint256 withdrawal_amount = amount > available_amount ? available_amount : amount;

		// Update stored amount
		total_tokens_stored[address(token)] -= withdrawal_amount;

		// Transfer tokens to recipient
		SafeERC20.safeTransfer(
			token,
			recipient,
			withdrawal_amount
		);

		emit TokensWithdrawn(address(token), recipient, withdrawal_amount, total_tokens_stored[address(token)]);
	}

	/// @notice Withdraws non-accounted tokens (difference between actual balance and tracked amount)
	/// @dev Only callable by the locks vault contract
	/// @param token Address of the token to withdraw excess amount
	/// @param recipient Address to receive the tokens
	/// @return withdrawn_amount Amount of excess tokens withdrawn
	function withdrawNonAccounted(IERC20 token, address recipient) external onlyLocksVault returns (uint256 withdrawn_amount) {
		require(recipient != address(0), "Cannot withdraw to zero address");
		require(address(token) != address(0), "Cannot withdraw zero address token");

		// Calculate the difference between actual balance and tracked amount
		uint256 actual_balance = token.balanceOf(address(this));
		uint256 tracked_amount = total_tokens_stored[address(token)];
		
		if (actual_balance <= tracked_amount) {
			return 0; // No excess tokens to withdraw
		}
		
		withdrawn_amount = actual_balance - tracked_amount;
		
		// Transfer excess tokens to recipient (don't update total_tokens_stored as these weren't tracked)
		SafeERC20.safeTransfer(
			token,
			recipient,
			withdrawn_amount
		);

		emit NonAccountedTokensWithdrawn(address(token), recipient, withdrawn_amount);
	}
}