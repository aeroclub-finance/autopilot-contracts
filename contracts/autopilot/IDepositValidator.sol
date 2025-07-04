// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../aerodrome/IveNFT.sol";

/// @title Deposit Validator Interface
/// @notice Interface for deposit validation contracts used by PermanentLocksPool
/// @dev This interface allows for different validation implementations
/// @author Aeroclub Team
interface IDepositValidator {

	/// @notice Validates if a deposit is allowed, reverts if not
	/// @param _nft_contract The veNFT contract
	/// @param _lock_id The lock ID to validate
	/// @param _depositor The address attempting to deposit
	function validateDepositOrFail(
		IveNFT _nft_contract,
		uint256 _lock_id,
		address _depositor
	) external view;
}