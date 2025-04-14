// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Pool} from "./Pool.sol";

/**
 * @title PoolFactory
 * @author Your Name
 * @notice Factory contract for creating and managing betting pools
 * @dev Uses minimal proxy pattern for gas-efficient pool deployment
 * @custom:security-contact security@yourproject.com
 */
contract PoolFactory is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Custom errors
    error InvalidPoolAddress();
    error InvalidParameters();
    error PoolNameExists();
    error InvalidPayment();

    // Constants
    uint256 private constant MAX_POOLS_PER_QUERY = 1000;
    uint256 private constant VERSION = 1;

    // State variables
    address[] private poolAddresses;
    address public immutable poolImplementation;
    mapping(uint256 => uint256) private _poolsCreatedInBlock;
    mapping(bytes32 => bool) private _poolNameExists;
    uint256 public activePoolCount;

    // Events
    event PoolCreated(
        address indexed poolAddress,
        address indexed creator,
        string sportType
    );
    event ContractUpgraded(uint256 version);

    // Storage gap for future upgrades
    uint256[45] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
        poolImplementation = address(new Pool());
    }

    /**
     * @notice Initializes the factory contract
     * @dev Sets up initial state and ownership
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        emit ContractUpgraded(VERSION);
    }

    /**
     * @notice Creates a new pool with validation
     * @dev Deploys a new minimal proxy and initializes it
     * @param poolName Name of the pool
     * @param fee Entry fee for the pool
     * @param maxPlayersAllowed Maximum number of players allowed
     * @param startDate Start date of the pool
     * @param duration Duration of the pool
     * @param poolOwner Owner of the pool
     * @param sportType Type of sport
     * @param serviceFeePercentage Service fee percentage
     * @param fixedPrizeAmount Fixed prize amount
     * @return address Address of the created pool
     */
    function createPool(
        string calldata poolName,
        uint256 fee,
        uint16 maxPlayersAllowed,
        uint256 startDate,
        uint64 duration,
        address poolOwner,
        string calldata sportType,
        uint32 serviceFeePercentage,
        uint256 fixedPrizeAmount,
        uint16 managementFeePercentage
    ) public payable whenNotPaused returns (address) {
        _poolsCreatedInBlock[block.number]++;

        if (poolOwner == address(0)) revert InvalidParameters();
        if (msg.value != fixedPrizeAmount) revert InvalidPayment();

        // Check pool name uniqueness
        bytes32 nameHash = keccak256(abi.encodePacked(poolName));
        if (_poolNameExists[nameHash]) revert PoolNameExists();
        _poolNameExists[nameHash] = true;

        address newPool = createClone(poolImplementation);
        try
            Pool(payable(newPool)).initialize{value: msg.value}(
                poolName,
                fee,
                maxPlayersAllowed,
                uint40(startDate),
                uint40(duration),
                poolOwner,
                sportType,
                uint8(serviceFeePercentage),
                fixedPrizeAmount,
                managementFeePercentage,
                msg.sender
            )
        {
            poolAddresses.push(newPool);
            activePoolCount++;

            emit PoolCreated(newPool, msg.sender, sportType);
            return newPool;
        } catch Error(string memory reason) {
            revert(
                string(abi.encodePacked("Pool initialization failed: ", reason))
            );
        } catch {
            revert("Pool initialization failed: unknown error");
        }
    }

    /**
     * @notice Returns all pool addresses
     * @return Array of all pool addresses
     */
    function getAllPoolAddresses() public view returns (address[] memory) {
        return poolAddresses;
    }

    /**
     * @notice Returns pools by sport type
     * @param sportType Type of sport to filter by
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return Array of matching pool addresses
     */
    function getPoolsBySportType(
        string calldata sportType,
        uint256 offset,
        uint256 limit
    ) public view returns (address[] memory) {
        if (limit > MAX_POOLS_PER_QUERY) {
            limit = MAX_POOLS_PER_QUERY;
        }

        address[] memory result = new address[](limit);
        uint256 count;
        uint256 length = poolAddresses.length;
        bytes32 sportTypeHash = keccak256(
            abi.encodePacked(_toLowerCase(sportType))
        );
        for (uint256 i = offset; i < length && count < limit; i++) {
            Pool pool = Pool(payable(poolAddresses[i]));
            if (
                keccak256(abi.encodePacked(_toLowerCase(pool.sportType()))) ==
                sportTypeHash
            ) {
                result[count] = poolAddresses[i];
                count++;
            }
        }

        assembly {
            mstore(result, count)
        }
        return result;
    }

    /**
     * @notice Returns the implementation version
     * @return Version number
     */
    function getImplementationVersion() external pure returns (uint256) {
        return VERSION;
    }

    /**
     * @dev Helper function to convert string to lowercase
     * @param str String to convert
     * @return Lowercase version of the string
     */
    function _toLowerCase(
        string memory str
    ) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }

        return string(bLower);
    }

    /**
     * @dev Creates a minimal proxy clone of the implementation
     * @param target Address of the implementation contract
     * @return result Address of the created clone
     */
    function createClone(address target) internal returns (address result) {
        // Convert address to bytes20 for assembly
        bytes20 targetBytes = bytes20(target);

        assembly {
            // Load free memory pointer
            let clone := mload(0x40)
            // Store minimal proxy initialization code
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            // Create new contract
            result := create(0, clone, 0x37)
        }
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * @dev Required by UUPSUpgradeable. Only owner can upgrade.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        emit ContractUpgraded(VERSION + 1);
    }
}
