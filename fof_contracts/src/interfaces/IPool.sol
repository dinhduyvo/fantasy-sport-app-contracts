// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPool
 * @dev Interface for the Pool contract
 * @notice Defines the external interface for interacting with betting pools
 */
interface IPool {
    // Custom errors
    error AlreadyParticipant();
    error InvalidStatus();
    error InvalidAmount();
    error TransferFailed();
    error PoolFull();
    error NoParticipants();
    error InvalidWinners();
    error ZeroAddress();
    error InvalidLength();
    error DuplicateWinner();
    error InvalidTimelock();
    error EmergencyCooldownNotPassed();

    // Events
    event ParticipantJoined(address indexed participant, uint256 amount);
    event PoolStatusChanged(uint8 indexed status, uint40 timestamp);
    event PaidForWinner(address indexed participant, uint256 amount);
    event PaidForService(address indexed ownerAddress, uint256 amount);
    event EmergencyWithdrawn(address indexed owner, uint256 amount);
    event ServiceFeeUpdated(uint8 oldFee, uint8 newFee);
    event PointsUpdated(address indexed participant, int32 points);
    event WinnersSelected(address[] winners);
    event InitializationTimelock(uint40 unlockTime);

    struct PoolInfo {
        string name;
        address creator;
        uint16 maxParticipants;
        uint256 joinFee;
        uint40 createdTime;
        uint40 startTime;
        uint40 endTime;
        address[] winner;
        uint8 status;
        uint40 duration;
        uint256 totalBalance;
        address[] participantAddresses;
        int32[] participantPoints;
        address owner;
        string sportType;
        uint256 fixedPrizeAmount;
        uint16 managementFeePercentage;
    }

    /**
     * @dev Initializes a new pool
     * @param poolName Name of the pool
     * @param fee Entry fee for the pool
     * @param maxParticipantsAllowed Maximum number of participants allowed
     * @param startDate Start date of the pool
     * @param duration Duration of the pool in seconds
     * @param poolOwner Address of the pool owner
     * @param sportType Type of sport for this pool
     * @param serviceFeePercentage Percentage of fee taken as service charge
     * @param fixedPrizeAmount Fixed prize amount
     * @param managementFeePercentage Percentage of fee taken as management fee
     */
    function initialize(
        string memory poolName,
        uint256 fee,
        uint16 maxParticipantsAllowed,
        uint256 startDate,
        uint40 duration,
        address poolOwner,
        string memory sportType,
        uint8 serviceFeePercentage,
        uint256 fixedPrizeAmount,
        uint16 managementFeePercentage
    ) external;

    /**
     * @dev Allows a participant to join the pool
     * @param playerIDs Array of player IDs picked by the participant
     */
    function joinPool(string[] calldata playerIDs) external payable;

    /**
     * @dev Starts the pool
     */
    function startPool() external;

    /**
     * @dev Ends the pool and distributes prizes
     * @param newPoints Array of points for each participant
     * @param winners Array of winner addresses
     * @param winnersDistribution Array of distribution percentages for winners
     */
    function endPool(
        int32[] calldata newPoints,
        address[] calldata winners,
        uint32[] calldata winnersDistribution
    ) external;

    /**
     * @dev Emergency withdrawal of pool funds
     */
    function emergencyWithdraw() external;

    /**
     * @dev Updates the service fee percentage
     * @param newPercentage New service fee percentage
     */
    function setServiceFeePercentage(uint8 newPercentage) external;

    /**
     * @dev Returns pool information
     */
    function getPoolInfo() external view returns (PoolInfo memory);

    /**
     * @dev Returns the sport type of the pool
     */
    function sportType() external view returns (string memory);

    /**
     * @dev Pauses the pool
     */
    function pause() external;

    /**
     * @dev Unpauses the pool
     */
    function unpause() external;

    /**
     * @dev Claims any pending payouts for the caller
     */
    function claimPayout() external;

    /**
     * @dev Returns the count of participants who picked a specific player
     * @param playerID The ID of the player to check
     * @return The number of participants who picked this player
     */
    function getPlayerPickCount(
        uint256 playerID
    ) external view returns (uint256);
}
