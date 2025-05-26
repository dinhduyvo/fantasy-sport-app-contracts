// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title Pool
 * @author Your Name
 * @notice A contract for managing betting pools with multiple participants
 * @dev Uses OpenZeppelin upgradeable contracts for security and flexibility
 * @custom:security-contact security@yourproject.com
 */
contract Pool is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
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
    error NotParticipant();
    error EmergencyStopActive();

    // Packed storage for gas optimization
    struct PoolConfig {
        uint40 createdTime;
        uint40 startTime;
        uint40 endTime;
        uint40 duration;
        uint40 lastEmergencyWithdraw;
        uint16 maxParticipants;
        uint8 status;
        uint8 serviceFeePercentage;
        bool emergencyStop;
    }

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
        mapping(address => uint256[]) pickedPlayers; // Cannot be included in struct due to Solidity limitations
    }

    // Extended PoolInfo for return values (without mappings)
    struct ExtendedPoolInfo {
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
        //string[][] participantPickedPlayers;
    }

    enum Status {
        Open,
        Running,
        Closed,
        Expired
    }

    // State variables
    PoolConfig private _config;
    string private _name;
    address private _owner;
    address private _creator;
    uint256 private _joinFee;
    string private _sportType;
    uint256 private _fixedPrizeAmount;
    uint16 private _managementFeePercentage;

    // Mappings
    mapping(address => bool) private _participants;
    mapping(address => int32) private _participantPoints;
    mapping(address => string[]) private _participantPickedPlayers;

    address[] private _participantAddresses;
    address[] private _winner;

    // Version for upgrades
    uint8 private constant VERSION = 1;

    // Events
    event ParticipantJoined(address indexed participant, uint256 amount);
    event PoolStatusChanged(Status indexed status, uint40 timestamp);
    event PaidForWinner(address indexed participant, uint256 amount);
    event PaidForService(address indexed ownerAddress, uint256 amount);
    event PaidForCreator(address indexed creator, uint256 amount);
    event EmergencyWithdrawn(address indexed owner, uint256 amount);
    event ServiceFeeUpdated(uint8 oldFee, uint8 newFee);
    event PointsUpdated(address indexed participant, int32 points);
    event WinnersSelected(address[] winners);
    event InitializationTimelock(uint40 unlockTime);
    event EmergencyStop(bool active);
    event PayoutClaimed(address indexed participant, uint256 amount);
    event PlayersSelected(address indexed participant, string[] playerIDs);
    event ContributionReceived(
        address indexed contributor,
        uint256 amount,
        string message
    );

    // Storage gap for future upgrades
    uint256[45] private __gap;

    // Add new state variables after the existing ones
    mapping(address => uint256) private _pendingPayouts;
    uint256 private _totalPendingPayouts;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the pool with given parameters
     * @dev Sets up initial state and validates all parameters
     * @param poolName Name of the pool
     * @param fee Entry fee for participants
     * @param maxParticipantsAllowed Maximum number of participants
     * @param startDate Start date of the pool
     * @param duration_ Duration of the pool in seconds
     * @param poolOwner Address of the pool owner
     * @param sportType_ Type of sport for this pool
     * @param serviceFeePercentage_ Percentage of fee taken as service charge
     * @param fixedPrizeAmount_ Fixed prize amount
     * @param managementFeePercentage_ Percentage of fee taken as management fee
     */
    function initialize(
        string calldata poolName,
        uint256 fee,
        uint16 maxParticipantsAllowed,
        uint256 startDate,
        uint40 duration_,
        address poolOwner,
        string calldata sportType_,
        uint8 serviceFeePercentage_,
        uint256 fixedPrizeAmount_,
        uint16 managementFeePercentage_,
        address creator_
    ) public payable initializer {
        // Input validation
        if (poolOwner == address(0)) revert ZeroAddress();
        if (msg.value != fixedPrizeAmount_) revert InvalidAmount();
        if (managementFeePercentage_ > 100) revert InvalidAmount();

        __Ownable_init(poolOwner);
        __Pausable_init();
        __ReentrancyGuard_init();

        _name = poolName;
        _creator = creator_;
        _owner = poolOwner;
        _joinFee = fee;
        _sportType = sportType_;
        _fixedPrizeAmount = fixedPrizeAmount_;
        _managementFeePercentage = managementFeePercentage_;
        _config = PoolConfig({
            createdTime: uint40(block.timestamp),
            startTime: uint40(startDate),
            endTime: uint40(startDate + duration_),
            duration: duration_,
            lastEmergencyWithdraw: uint40(block.timestamp),
            maxParticipants: maxParticipantsAllowed,
            status: uint8(Status.Open),
            serviceFeePercentage: serviceFeePercentage_,
            emergencyStop: false
        });

        _transferOwnership(poolOwner);

        emit InitializationTimelock(uint40(startDate));
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}

    /**
     * @notice Modifier to check emergency stop
     */
    modifier whenNotStopped() {
        if (_config.emergencyStop) revert EmergencyStopActive();
        _;
    }

    /**
     * @dev Internal function to check if all winners are valid participants
     * @param winners Array of winner addresses to validate
     */
    function _validateWinners(address[] memory winners) private view {
        for (uint i = 0; i < winners.length; i++) {
            if (!_participants[winners[i]]) revert NotParticipant();
        }
    }

    /**
     * @notice Allows a participant to join the pool
     * @dev Requires exact fee payment and validates pool state
     * @param playerIDs Array of player IDs picked by the participant
     */
    function joinPool(
        string[] calldata playerIDs
    ) external payable whenNotPaused whenNotStopped nonReentrant {
        if (_config.status != uint8(Status.Open)) revert InvalidStatus();
        if (_participants[msg.sender]) revert AlreadyParticipant();
        if (_participantAddresses.length >= _config.maxParticipants)
            revert PoolFull();
        if (msg.value != _joinFee) revert InvalidAmount();

        _participants[msg.sender] = true;
        _participantAddresses.push(msg.sender);
        _participantPoints[msg.sender] = 0;
        _participantPickedPlayers[msg.sender] = playerIDs;

        emit ParticipantJoined(msg.sender, msg.value);
        emit PlayersSelected(msg.sender, playerIDs);
    }

    /**
     * @notice Starts the pool
     * @dev Can only be called by owner when pool is open
     */
    function startPool()
        external
        onlyOwner
        whenNotPaused
        whenNotStopped
    {
        if (_config.status != uint8(Status.Open)) revert InvalidStatus();

        _config.status = uint8(Status.Running);
        _config.startTime = uint40(block.timestamp);
        emit PoolStatusChanged(Status.Running, uint40(block.timestamp));
    }

    /**
     * @notice Ends the pool and distributes prizes
     * @dev Validates winners and distributes prizes according to points
     * @param newPoints Array of points for each participant
     * @param winners Array of winner addresses
     */
    function endPool(
        int32[] memory newPoints,
        address[] memory winners,
        uint32[] memory winnersDistribution
    ) public payable onlyOwner {
        require(
            _config.status == uint8(Status.Running),
            "Pool must be running"
        );

        // Update points if provided
        if (newPoints.length > 0) {
            for (uint256 i = 0; i < _participantAddresses.length; i++) {
                _participantPoints[_participantAddresses[i]] = newPoints[i];
                emit PointsUpdated(_participantAddresses[i], newPoints[i]);
            }
        }

        // Process winners if provided
        if (winners.length > 0) {
            require(
                winners.length == winnersDistribution.length,
                "Array lengths mismatch"
            );

            // Validate winners
            _validateWinners(winners);

            _winner = winners;

            // Calculate total distribution percentage
            uint256 totalDistribution;
            for (uint i = 0; i < winnersDistribution.length; i++) {
                totalDistribution += winnersDistribution[i];
            }
            require(totalDistribution <= 100, "Distribution exceeds 100%");

            // Calculate total payout based on pool type
            uint256 totalPayout;
            if (_fixedPrizeAmount > 0) {
                // Fixed prize pool: distribute 100% of fixed prize amount
                totalPayout = _fixedPrizeAmount;
            } else {
                // Non-fixed prize pool: distribute 90% of current balance
                totalPayout = (address(this).balance * 90) / 100;
            }

            // Validate sufficient balance for payout
            if (address(this).balance < totalPayout) {
                revert InvalidAmount();
            }

            uint256 totalPaid;

            // Transfer payouts to winners
            for (uint i = 0; i < winners.length; i++) {
                if (winners[i] == address(0)) continue;

                uint256 payoutAmount = (totalPayout * winnersDistribution[i]) /
                    100;
                totalPaid += payoutAmount;

                (bool success, ) = winners[i].call{value: payoutAmount}("");
                require(success, "Transfer to winner failed");
                emit PaidForWinner(winners[i], payoutAmount);
            }
        }

        // Transfer to owner as (100 - managementFeePercentage)% of remaining balance
        uint256 creatorFee = (address(this).balance *
            (100 - _managementFeePercentage)) / 100;
        if (creatorFee > 0) {
            (bool successCreator, ) = _creator.call{value: creatorFee}("");
            require(successCreator, "Transfer to creator failed");
            emit PaidForCreator(_creator, creatorFee);
        }

        // Transfer remaining balance to owner as service fee
        uint256 remainingBalance = address(this).balance;
        if (remainingBalance > 0) {
            (bool successService, ) = _owner.call{value: remainingBalance}("");
            require(successService, "Transfer to service failed");
            emit PaidForService(_owner, remainingBalance);
        }

        _config.status = uint8(Status.Closed);
        _config.endTime = uint40(block.timestamp);
        emit PoolStatusChanged(Status.Closed, uint40(block.timestamp));
    }

    /**
     * @notice Emergency withdrawal with cooldown period
     * @dev Can only be called by owner and has a cooldown period
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance <= 0) revert InvalidAmount();

        _config.lastEmergencyWithdraw = uint40(block.timestamp);

        (bool success, ) = _owner.call{value: balance}("");
        if (!success) revert TransferFailed();

        emit EmergencyWithdrawn(_owner, balance);
    }

    /**
     * @notice Activates emergency stop
     * @dev Can only be called by owner
     */
    function setEmergencyStop(bool active) external onlyOwner {
        _config.emergencyStop = active;
        emit EmergencyStop(active);
    }

    /**
     * @notice Updates the service fee percentage
     * @dev Can only be called by owner
     * @param newPercentage New service fee percentage
     */
    function setServiceFeePercentage(uint8 newPercentage) external onlyOwner {
        if (newPercentage > 100) revert InvalidAmount();
        uint8 oldFee = _config.serviceFeePercentage;
        _config.serviceFeePercentage = newPercentage;
        emit ServiceFeeUpdated(oldFee, newPercentage);
    }

    /**
     * @notice Returns pool information
     * @return Extended pool information including picked players
     */
    function getPoolInfo() external view returns (ExtendedPoolInfo memory) {
        return
            ExtendedPoolInfo({
                name: _name,
                creator: _creator,
                maxParticipants: _config.maxParticipants,
                joinFee: _joinFee,
                createdTime: _config.createdTime,
                startTime: _config.startTime,
                endTime: _config.endTime,
                winner: _winner,
                status: _config.status,
                duration: _config.duration,
                totalBalance: address(this).balance,
                participantAddresses: _participantAddresses,
                participantPoints: _getParticipantPoints(),
                owner: _owner,
                sportType: _sportType,
                fixedPrizeAmount: _fixedPrizeAmount,
                managementFeePercentage: _managementFeePercentage
                //participantPickedPlayers: _getParticipantPickedPlayers()
            });
    }

    /**
     * @notice Returns the picked players for a specific participant
     * @param participant Address of the participant
     * @return Array of player IDs picked by the participant
     */
    function getPickedPlayers(
        address participant
    ) external view returns (string[] memory) {
        if (!_participants[participant]) revert NotParticipant();
        return _participantPickedPlayers[participant];
    }

    /**
     * @notice Returns the implementation version
     * @return Version number
     */
    function getImplementationVersion() external pure returns (uint256) {
        return VERSION;
    }

    /**
     * @dev Helper function to get participant points
     */
    function _getParticipantPoints()
        private
        view
        returns (int32[] memory points)
    {
        points = new int32[](_participantAddresses.length);
        for (uint256 i = 0; i < _participantAddresses.length; i++) {
            points[i] = _participantPoints[_participantAddresses[i]];
        }
    }

    /**
     * @dev Helper function to get picked players for all participants
     */
    function _getParticipantPickedPlayers()
        private
        view
        returns (string[][] memory pickedPlayers)
    {
        pickedPlayers = new string[][](_participantAddresses.length);
        for (uint256 i = 0; i < _participantAddresses.length; i++) {
            address participant = _participantAddresses[i];
            string[] memory playerIDs = _participantPickedPlayers[participant];
            pickedPlayers[i] = playerIDs;
        }
    }

    /**
     * @dev Helper function to check if an address exists in an array
     */
    function _contains(
        address[] memory addresses,
        address target
    ) private pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) return true;
        }
        return false;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Returns the sport type
     * @return Sport type string
     */
    function sportType() external view returns (string memory) {
        return _sportType;
    }

    /**
     * @notice Returns the fixed prize amount
     * @return fixedPrizeAmount
     */
    function fixedPrizeAmount() external view returns (uint256) {
        return _fixedPrizeAmount;
    }

    /**
     * @notice Get a list of all unique player IDs selected by participants
     * @dev Returns a deduplicated list of all player IDs used in this pool
     * @return Array of unique player IDs
     */
    function getAllPlayerIDs() external view returns (string[] memory) {
        // First count the maximum possible size (all picked players)
        uint256 maxSize = 0;
        for (uint256 i = 0; i < _participantAddresses.length; i++) {
            maxSize += _participantPickedPlayers[_participantAddresses[i]]
                .length;
        }

        if (maxSize == 0) {
            return new string[](0);
        }

        // Temporary storage for all IDs
        string[] memory allIDs = new string[](maxSize);
        uint256 idCount = 0;

        // Add all IDs
        for (uint256 i = 0; i < _participantAddresses.length; i++) {
            string[] memory playerIDs = _participantPickedPlayers[
                _participantAddresses[i]
            ];
            for (uint256 j = 0; j < playerIDs.length; j++) {
                allIDs[idCount] = playerIDs[j];
                idCount++;
            }
        }

        // Now count unique IDs using a naive approach (O(n²) but with small n it's fine)
        uint256 uniqueCount = 0;
        bool[] memory isUnique = new bool[](idCount);

        for (uint256 i = 0; i < idCount; i++) {
            if (!isUnique[i]) {
                // This is a new unique ID
                uniqueCount++;

                // Mark all duplicates
                for (uint256 j = i + 1; j < idCount; j++) {
                    if (
                        keccak256(bytes(allIDs[i])) ==
                        keccak256(bytes(allIDs[j]))
                    ) {
                        isUnique[j] = true;
                    }
                }
            }
        }

        // Create the final array with unique IDs
        string[] memory uniqueIDs = new string[](uniqueCount);
        uint256 uniqueIndex = 0;

        for (uint256 i = 0; i < idCount; i++) {
            if (!isUnique[i]) {
                uniqueIDs[uniqueIndex] = allIDs[i];
                uniqueIndex++;
            }
        }

        return uniqueIDs;
    }

    /**
     * @notice Returns the count of participants who picked a specific player
     * @param playerID The ID of the player to check
     * @return The number of participants who picked this player
     */
    function getPlayerPickCount(
        string calldata playerID
    ) external view returns (uint256) {
        uint256 count = 0;

        for (uint256 i = 0; i < _participantAddresses.length; i++) {
            string[] memory playerIDs = _participantPickedPlayers[
                _participantAddresses[i]
            ];

            for (uint256 j = 0; j < playerIDs.length; j++) {
                if (
                    keccak256(bytes(playerIDs[j])) == keccak256(bytes(playerID))
                ) {
                    count++;
                    break; // Each participant can only pick a player once
                }
            }
        }

        return count;
    }

    /**
     * @notice Claim pending payouts
     * @dev Allows winners to claim their prizes using pull pattern
     */
    function claimPayout() external nonReentrant {
        uint256 amount = _pendingPayouts[msg.sender];
        if (amount == 0) revert InvalidAmount();

        _pendingPayouts[msg.sender] = 0;
        _totalPendingPayouts -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit PayoutClaimed(msg.sender, amount);
    }
}
