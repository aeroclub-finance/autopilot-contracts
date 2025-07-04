// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../aerodrome/IveNFT.sol";
import "./IDepositValidator.sol";

/// @title Deposit Validator Contract V1
/// @notice Validates deposits for PermanentLocksPool contracts
/// @dev This contract can be updated/replaced by the pool contract owner
/// @author Aeroclub Team
contract DepositValidatorV1 is IDepositValidator {

	/// @notice Minimum voting power required for deposit
	uint256 public minimum_lock_amount;

	/// @notice Contract owner with administrative privileges
	address public owner;

	// ============================================================================
	// EVENTS
	// ============================================================================

	/// @notice Emitted when minimum lock amount is updated
	/// @param old_minimum Previous minimum lock amount
	/// @param new_minimum New minimum lock amount
	event MinimumLockAmountUpdated(uint256 old_minimum, uint256 new_minimum);

	// ============================================================================
	// MODIFIERS
	// ============================================================================

	/// @notice Restricts access to contract owner only
	modifier onlyOwner() {
		require(msg.sender == owner, "Not owner");
		_;
	}

	// ============================================================================
	// CONSTRUCTOR
	// ============================================================================

	/// @notice Initializes the deposit validator
	/// @param _minimum_lock_amount Initial minimum lock amount
	constructor(uint256 _minimum_lock_amount) {
		owner = msg.sender;
		minimum_lock_amount = _minimum_lock_amount;
	}

	// ============================================================================
	// VALIDATION FUNCTIONS
	// ============================================================================

	/// @notice Validates if a deposit is allowed, reverts if not
	/// @param _nft_contract The veNFT contract
	/// @param _lock_id The lock ID to validate
	function validateDepositOrFail(
		IveNFT _nft_contract,
		uint256 _lock_id,
		address /* _depositor */
	) external view {
		uint256 amount = _nft_contract.balanceOfNFT(_lock_id);
		require(amount >= minimum_lock_amount, "Lock amount below minimum");
	}

	// ============================================================================
	// OWNER FUNCTIONS
	// ============================================================================

	/// @notice Sets minimum lock amount required for deposits
	/// @dev Only owner can call this function
	/// @param _minimum_lock_amount New minimum voting power required for deposit
	function setMinimumLockAmount(uint256 _minimum_lock_amount) external onlyOwner {
		uint256 old_minimum = minimum_lock_amount;
		minimum_lock_amount = _minimum_lock_amount;
		emit MinimumLockAmountUpdated(old_minimum, _minimum_lock_amount);
	}

	/// @notice Transfers ownership to a new address
	/// @dev Only owner can call this function
	/// @param _new_owner New owner address
	function transferOwnership(address _new_owner) external onlyOwner {
		require(_new_owner != address(0), "Cannot transfer to zero address");
		owner = _new_owner;
	}
}