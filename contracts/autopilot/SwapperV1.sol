// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PermanentLocksPool.sol";

/// @title Universal Router Interface
/// @dev Interface for interacting with the Universal Router for token swaps
interface IUniversalRouter {
    /// @notice Execute a series of commands with encoded inputs
    /// @param commands The commands to execute
    /// @param inputs The inputs to use for each command
    /// @param deadline The timestamp after which the transaction will revert
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;

    /// @notice Route structure for token paths
    /// @dev Used to define swap paths for tokens
    struct Route {
        address from;
        address to;
        bool stable;
    }
}

/// @title Autopilot Swapper V1
/// @notice Contract for swapping tokens collected from rewards and sending them to the locks pool
/// @dev Works in conjunction with PermanentLocksPool to manage rewards
contract SwapperV1 {
    using SafeERC20 for IERC20;
    
    /// @notice Universal Router used for swapping tokens
    IUniversalRouter public immutable router;
    
    /// @notice Reference to the locks pool contract
    PermanentLocksPool public immutable locks_pool;
    
    /// @notice Token used for rewards distribution
    IERC20 public immutable rewards_token;
    
    /// @notice Owner of this contract
    address public owner;
    
    /// @notice Emitted when contract ownership is transferred
    /// @param previous_owner Address of the previous owner
    /// @param new_owner Address of the new owner
    event OwnershipTransferred(address indexed previous_owner, address indexed new_owner);

    /// @notice Restricts function access to contract owner only
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    /// @notice Restricts function access to permitted operators from locks pool
    modifier onlyPermitted() {
        require(locks_pool.permitted_operators(msg.sender), "Not a permitted operator in locks pool");
        _;
    }

    /// @notice Initializes the contract with required dependencies
    /// @param _router Address of the Universal Router contract
    /// @param _locks_pool Address of the PermanentLocksPool contract
    constructor(IUniversalRouter _router, PermanentLocksPool _locks_pool) {
        router = _router;
        locks_pool = _locks_pool;
        rewards_token = _locks_pool.rewards_token();
        owner = msg.sender;
    }
    
    /// @notice Transfers ownership of the contract to a new address
    /// @param new_owner Address of the new owner
    function transferOwnership(address new_owner) external onlyOwner {
        require(new_owner != address(0), "New owner is zero address");
        address previous_owner = owner;
        owner = new_owner;
        emit OwnershipTransferred(previous_owner, new_owner);
    }
    
    /// @notice Takes a snapshot of current rewards and sends them to the locks pool
    /// @dev Calculates current rewards token balance and sends it to the locks pool contract
    function snapshotRewards() external onlyPermitted {
        uint256 current_rewards_balance = rewards_token.balanceOf(address(this));
        
        // Approve locks pool to transfer rewards tokens from this contract
        if (current_rewards_balance > 0) {
            rewards_token.forceApprove(address(locks_pool), current_rewards_balance);
        }
        
        locks_pool.snapshotRewards(current_rewards_balance);
    }

    /// @notice Performs multiple token swaps through the Universal Router
    /// @dev Only permitted operators can call this function
    /// @param commands Array of command bytes for the router
    /// @param inputs Array of input arrays for each command
    /// @param deadlines Array of deadlines for each swap
    function batchSwapMultiHop(
        bytes[] calldata commands,
        bytes[][] calldata inputs,
        uint256[] calldata deadlines
    ) external onlyPermitted {
        uint256 n = commands.length;
        require(
            n == commands.length &&
            n == inputs.length &&
            n == deadlines.length,
            "length mismatch"
        );

        for (uint256 i = 0; i < n; i++) {
            // read first byte from `bytes`
            uint8 first_command = uint8(commands[i][0]);
            address from_token;
            uint256 amount_in;
            
            if(first_command == 0x08) {
                // V2 swap path
                // abi decode "address", "uint256", "uint256", "tuple(address from,address to,bool stable)[]", "bool",
                IUniversalRouter.Route[] memory path;
                (
                    ,
                    amount_in,
                    ,
                    path,
                ) = abi.decode(inputs[i][0], (address, uint256, uint256, IUniversalRouter.Route[], bool));

                from_token = path[0].from;
            } else if (first_command == 0x00) {
                // V3 swap path
                // abi decode "address", "uint256", "uint256", "bytes", "bool",
                bytes memory path;
                (
                    ,
                    amount_in,
                    ,
                    path,
                ) = abi.decode(inputs[i][0], (address, uint256, uint256, bytes, bool));
                
                // Extract first address (20 bytes) from the packed path
                require(path.length >= 20, "Invalid path length");
                from_token = address(0);
                assembly {
                    // Load the first 32 bytes, but we only need the first 20 bytes for the address
                    let first_word := mload(add(path, 32))
                    // Shift right to get only the 20 bytes we need (12 bytes of padding * 8 bits = 96)
                    from_token := shr(96, first_word)
                }
            } else {
                revert("unknown command");
            }

            // Use forceApprove instead of safeApprove (which is deprecated)
            IERC20(from_token).forceApprove(address(router), amount_in);

            // swap and enforce slippage
            router.execute(
                commands[i],
                inputs[i],
                deadlines[i]
            );
        }
    }
}
