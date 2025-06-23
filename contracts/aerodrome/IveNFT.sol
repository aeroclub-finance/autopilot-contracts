// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/**
 * @title IveNFT Interface
 * @notice Interface for Voting Escrow NFTs (veNFTs) based on Aerodrome Finance
 * @dev This interface combines essential veNFT functionality for the Aeroclub project
 */
interface IveNFT {
    // Structs
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }

    struct UserPoint {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
        uint256 permanent;
    }

    struct GlobalPoint {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
        uint256 permanentLockBalance;
    }

    struct Checkpoint {
        uint256 fromTimestamp;
        address owner;
        uint256 delegatedBalance;
        uint256 delegatee;
    }

    // Enums
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    enum EscrowType {
        NORMAL,
        LOCKED,
        MANAGED
    }

    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    
    event Deposit(
        address indexed provider,
        uint256 indexed tokenId,
        DepositType indexed depositType,
        uint256 value,
        uint256 locktime,
        uint256 ts
    );
    event Withdraw(address indexed provider, uint256 indexed tokenId, uint256 value, uint256 ts);
    event LockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
    event UnlockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
    event Supply(uint256 prevSupply, uint256 supply);
    
    event Merge(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint256 _amountFrom,
        uint256 _amountTo,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _ts
    );
    
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _locktime,
        uint256 _ts
    );

    // Core veNFT Functions
    function token() external view returns (address);
    function tokenId() external view returns (uint256);
    function supply() external view returns (uint256);
    function permanentLockBalance() external view returns (uint256);
    function epoch() external view returns (uint256);

    // ERC721 Functions
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    // Lock Management
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function createLock(uint256 value, uint256 lockDuration) external returns (uint256);
    function createLockFor(uint256 value, uint256 lockDuration, address to) external returns (uint256);
    function increaseAmount(uint256 tokenId, uint256 value) external;
    function increaseUnlockTime(uint256 tokenId, uint256 lockDuration) external;
    function withdraw(uint256 tokenId) external;
    function merge(uint256 from, uint256 to) external;
    function split(uint256 from, uint256 amount) external returns (uint256 tokenId1, uint256 tokenId2);

    // Permanent Locks
    function lockPermanent(uint256 tokenId) external;
    function unlockPermanent(uint256 tokenId) external;

    // Voting Power
    function balanceOfNFT(uint256 tokenId) external view returns (uint256);
    function balanceOfNFTAt(uint256 tokenId, uint256 timestamp) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 timestamp) external view returns (uint256);

    // Delegation
    function delegates(uint256 delegator) external view returns (uint256);
    function delegate(uint256 delegator, uint256 delegatee) external;
    function getPastVotes(address account, uint256 tokenId, uint256 timestamp) external view returns (uint256);
    function getPastTotalSupply(uint256 timestamp) external view returns (uint256);

    // Voting State
    function voted(uint256 tokenId) external view returns (bool);
    function voting(uint256 tokenId, bool voted) external;

    // Managed NFTs
    function escrowType(uint256 tokenId) external view returns (EscrowType);
    function createManagedLockFor(address to) external returns (uint256);
    function depositManaged(uint256 tokenId, uint256 mTokenId) external;
    function withdrawManaged(uint256 tokenId) external;
    function weights(uint256 tokenId, uint256 mTokenId) external view returns (uint256);
    function deactivated(uint256 tokenId) external view returns (bool);

    // Checkpoints
    function checkpoint() external;
    function userPointHistory(uint256 tokenId, uint256 loc) external view returns (UserPoint memory);
    function pointHistory(uint256 loc) external view returns (GlobalPoint memory);
    function numCheckpoints(uint256 tokenId) external view returns (uint48);
    function checkpoints(uint256 tokenId, uint48 index) external view returns (Checkpoint memory);

    // Utility
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
    function canSplit(address account) external view returns (bool);
    function slopeChanges(uint256 timestamp) external view returns (int128);
}