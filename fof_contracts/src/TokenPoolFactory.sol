// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TokenPool} from "./TokenPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FOFToken} from "./FOFToken.sol";

/**
 * @title TokenPoolFactory
 * @author Your Name
 * @notice Factory contract for creating and managing ERC20 token betting pools
 * @dev Uses minimal proxy pattern for gas-efficient pool deployment
 * @custom:security-contact security@yourproject.com
 */
contract TokenPoolFactory is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    // Custom errors
    error InvalidPoolAddress();
    error InvalidParameters();
    error PoolNameExists();
    error InvalidToken();
    error InsufficientAllowance();

    // Constants
    uint256 private constant MAX_POOLS_PER_QUERY = 1000;
    uint256 private constant VERSION = 1;

    // State variables
    address[] private poolAddresses;
    address public immutable tokenPoolImplementation;
    mapping(uint256 => uint256) private _poolsCreatedInBlock;
    mapping(bytes32 => bool) private _poolNameExists;
    mapping(address => address[]) private _poolsByToken;
    uint256 public activePoolCount;
    FOFToken public fofToken;

    // Structs
    struct TokenPoolParams {
        string poolName;
        uint256 fee;
        uint16 maxPlayersAllowed;
        uint256 startDate;
        uint64 duration;
        address poolOwner;
        string sportType;
        uint32 serviceFeePercentage;
        uint256 fixedPrizeAmount;
        uint16 managementFeePercentage;
        address tokenAddress;
    }

    // Events
    event TokenPoolCreated(
        address indexed poolAddress,
        address indexed creator,
        address indexed tokenAddress,
        string sportType
    );
    event ContractUpgraded(uint256 version);

    // Storage gap for future upgrades (reduced to account for new variables)
    uint256[43] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
        tokenPoolImplementation = address(new TokenPool());
    }

    /**
     * @notice Initializes the factory contract
     * @dev Sets up initial state and ownership
     */
    function initialize(address fofTokenAddress_) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        fofToken = FOFToken(fofTokenAddress_);
        emit ContractUpgraded(VERSION);
    }

    /**
     * @notice Creates a new token pool with validation
     * @dev Deploys a new minimal proxy and initializes it
     * @param params TokenPoolParams struct containing all pool parameters
     * @return address Address of the created pool
     */
    function createTokenPool(
        TokenPoolParams calldata params
    ) public whenNotPaused returns (address) {
        _poolsCreatedInBlock[block.number]++;

        if (params.poolOwner == address(0)) revert InvalidParameters();

        // Check pool name uniqueness
        bytes32 nameHash = keccak256(abi.encodePacked(params.poolName));
        if (_poolNameExists[nameHash]) revert PoolNameExists();
        _poolNameExists[nameHash] = true;

        // Check if creator has sufficient tokens for fixed prize if required
        if (params.fixedPrizeAmount > 0) {
            IERC20 token = IERC20(params.tokenAddress);
            if (token.balanceOf(msg.sender) < params.fixedPrizeAmount) {
                revert InsufficientAllowance();
            }
            if (token.allowance(msg.sender, address(this)) < params.fixedPrizeAmount) {
                revert InsufficientAllowance();
            }
        }

        address newPool = createClone(tokenPoolImplementation);
        try
            TokenPool(newPool).initialize(
                params.poolName,
                params.fee,
                params.maxPlayersAllowed,
                uint40(params.startDate),
                uint40(params.duration),
                params.poolOwner,
                params.sportType,
                uint8(params.serviceFeePercentage),
                params.fixedPrizeAmount,
                params.managementFeePercentage,
                msg.sender,
                params.tokenAddress,
                address(fofToken)
            )
        {
            poolAddresses.push(newPool);
            _poolsByToken[params.tokenAddress].push(newPool);
            activePoolCount++;

            // Transfer fixed prize amount from creator to the pool if specified
            if (params.fixedPrizeAmount > 0) {
                IERC20(params.tokenAddress).safeTransferFrom(
                    msg.sender, 
                    newPool, 
                    params.fixedPrizeAmount
                );
            }

            emit TokenPoolCreated(newPool, msg.sender, params.tokenAddress, params.sportType);
            return newPool;
        } catch Error(string memory reason) {
            revert(
                string(abi.encodePacked("Token pool initialization failed: ", reason))
            );
        } catch {
            revert("Token pool initialization failed: unknown error");
        }
    }

    /**
     * @notice Returns all token pool addresses
     * @return Array of all pool addresses
     */
    function getAllTokenPoolAddresses() public view returns (address[] memory) {
        return poolAddresses;
    }

    /**
     * @notice Returns pools by token address
     * @param tokenAddress Address of the token to filter by
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return Array of matching pool addresses
     */
    function getPoolsByToken(
        address tokenAddress,
        uint256 offset,
        uint256 limit
    ) public view returns (address[] memory) {
        if (limit > MAX_POOLS_PER_QUERY) {
            limit = MAX_POOLS_PER_QUERY;
        }

        address[] memory tokenPools = _poolsByToken[tokenAddress];
        uint256 length = tokenPools.length;
        
        if (offset >= length) {
            return new address[](0);
        }

        uint256 end = offset + limit;
        if (end > length) {
            end = length;
        }

        address[] memory result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = tokenPools[i];
        }

        return result;
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
            TokenPool pool = TokenPool(poolAddresses[i]);
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
     * @notice Returns pools by sport type and token address
     * @param sportType Type of sport to filter by
     * @param tokenAddress Address of the token to filter by
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return Array of matching pool addresses
     */
    function getPoolsBySportTypeAndToken(
        string calldata sportType,
        address tokenAddress,
        uint256 offset,
        uint256 limit
    ) public view returns (address[] memory) {
        if (limit > MAX_POOLS_PER_QUERY) {
            limit = MAX_POOLS_PER_QUERY;
        }

        address[] memory tokenPools = _poolsByToken[tokenAddress];
        address[] memory result = new address[](limit);
        uint256 count;
        uint256 length = tokenPools.length;
        bytes32 sportTypeHash = keccak256(
            abi.encodePacked(_toLowerCase(sportType))
        );
        
        for (uint256 i = offset; i < length && count < limit; i++) {
            TokenPool pool = TokenPool(tokenPools[i]);
            if (
                keccak256(abi.encodePacked(_toLowerCase(pool.sportType()))) ==
                sportTypeHash
            ) {
                result[count] = tokenPools[i];
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
     * @notice Returns the count of pools using a specific token
     * @param tokenAddress Address of the token
     * @return Number of pools using the token
     */
    function getPoolCountByToken(address tokenAddress) external view returns (uint256) {
        return _poolsByToken[tokenAddress].length;
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
        address /* newImplementation */
    ) internal override onlyOwner {
        emit ContractUpgraded(VERSION + 1);
    }
}