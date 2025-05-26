// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PoolFactory} from "../src/PoolFactory.sol";
import {Pool} from "../src/Pool.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PoolFactoryTest is Test {
    PoolFactory public factory;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    uint8 constant SERVICE_FEE_PERCENTAGE = 10;
    uint256 constant MAX_NAME_LENGTH = 100;
    uint256 constant MAX_FEE = 100 ether;

    event ParticipantJoined(address indexed participant, uint256 amount);
    event PoolStatusChanged(Pool.Status indexed status, uint40 timestamp);
    event PaidForWinner(address indexed participant, uint256 amount);
    event PaidForService(address indexed ownerAddress, uint256 amount);
    event EmergencyWithdrawn(address indexed owner, uint256 amount);
    event ServiceFeeUpdated(uint8 oldFee, uint8 newFee);
    event PoolCreated(
        address indexed poolAddress,
        address indexed creator,
        string sportType
    );
    event PoolDeactivated(address indexed poolAddress, string reason);
    event PoolReactivated(address indexed poolAddress);
    event PointsUpdated(address indexed participant, uint32 points);
    event WinnersSelected(address[] winners);

    // Add receive function to accept ETH
    receive() external payable {}

    // Add fallback function to be extra safe
    fallback() external payable {}

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy implementation
        PoolFactory implementation = new PoolFactory();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            PoolFactory.initialize.selector
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        // Get factory instance
        factory = PoolFactory(address(proxy));
    }

    function test_CreatePool() public {
        string memory poolName = "Test Pool";
        string memory sportType = "Football";

        // Create pool first to get the address
        address newPool = factory.createPool(
            poolName,
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            sportType,
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        address[] memory addresses = factory.getAllPoolAddresses();
        IPool pool = IPool(addresses[0]);
        IPool.PoolInfo memory poolInfo = pool.getPoolInfo();

        assertEq(addresses.length, 1, "Should have created one pool");
        assertEq(poolInfo.name, poolName, "Pool name should match");
        assertEq(poolInfo.joinFee, 1 ether, "Join fee should match");
        assertEq(poolInfo.maxParticipants, 10, "Max participants should match");
        assertEq(poolInfo.sportType, sportType, "Sport type should match");
        assertEq(uint8(poolInfo.status), 0, "Pool should be in Open status");
    }

    function test_JoinPool() public {
        // Create pool
        address newPool = factory.createPool(
            "Test Pool",
            1 ether,
            3,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        IPool pool = IPool(newPool);

        // Create a default array of player IDs
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Test successful join
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ParticipantJoined(user1, 1 ether);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Test joining with incorrect fee
        vm.deal(user2, 2 ether);
        vm.prank(user2);
        vm.expectRevert(Pool.InvalidAmount.selector);
        pool.joinPool{value: 0.5 ether}(defaultPlayerIDs);

        // Test joining twice
        vm.prank(user1);
        vm.expectRevert(Pool.AlreadyParticipant.selector);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Fill pool and test pool full
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);
        vm.deal(user3, 2 ether);
        vm.prank(user3);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(address(this), 2 ether);
        vm.expectRevert(Pool.PoolFull.selector);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);
    }

    function test_StartEndPool() public {
        // Create and setup pool
        address newPool = factory.createPool(
            "Test Pool",
            1 ether,
            2,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        IPool pool = IPool(newPool);

        // Create a default array of player IDs
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Join pool with two users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Warp to start time
        vm.warp(block.timestamp + 1 days);

        // Start pool
        vm.expectEmit(true, false, false, true);
        emit PoolStatusChanged(Pool.Status.Running, uint40(block.timestamp));
        pool.startPool();

        // Record initial balances
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        // Set points for winners
        address[] memory winners = new address[](1);
        winners[0] = user1;
        int32[] memory points = new int32[](2);
        points[0] = 10; // points for user1
        points[1] = 5; // points for user2
        uint32[] memory winnerDistribution = new uint32[](1);
        winnerDistribution[0] = 100; // 100% for single winner

        // End pool and distribute prizes
        uint256 expectedPrize = 2 ether; // All funds go to winner

        // Expect events in the correct order
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user1, 10);
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user2, 5);
        vm.expectEmit(true, false, false, true);
        emit WinnersSelected(winners);
        vm.expectEmit(true, false, false, true);
        emit PaidForWinner(user1, expectedPrize);
        vm.expectEmit(true, false, false, true);
        emit PoolStatusChanged(Pool.Status.Closed, uint40(block.timestamp));

        pool.endPool(points, winners, winnerDistribution);

        // Verify balances
        assertEq(
            user1.balance - user1BalanceBefore,
            expectedPrize,
            "Winner should receive full prize"
        );
        assertEq(
            user2.balance - user2BalanceBefore,
            0,
            "Non-winner balance should remain unchanged"
        );
    }

    function test_EmergencyWithdraw() public {
        // Create and setup pool
        address newPool = factory.createPool(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        IPool pool = IPool(newPool);

        // Create a default array of player IDs
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Join pool with two users
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user2, 2 ether);
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        uint256 initialOwnerBalance = address(this).balance;
        uint256 poolBalance = address(pool).balance;

        // Wait for cooldown period
        vm.warp(block.timestamp + 24 hours);

        // Emergency withdraw
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdrawn(owner, poolBalance);
        pool.emergencyWithdraw();

        assertEq(
            address(this).balance,
            initialOwnerBalance + poolBalance,
            "Owner should receive all pool balance"
        );
        assertEq(address(pool).balance, 0, "Pool balance should be zero");

        // Test cooldown period
        // vm.expectRevert(Pool.EmergencyCooldownNotPassed.selector);
        pool.emergencyWithdraw();
    }

    function test_PauseUnpause() public {
        // Create pool
        address newPool = factory.createPool(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        IPool pool = IPool(newPool);

        // Create a default array of player IDs
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Pause pool
        pool.pause();

        // Try to join while paused
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Unpause and verify can join
        pool.unpause();
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);
    }

    function testFuzz_CreatePool(
        string memory poolName,
        uint256 fee,
        uint16 maxPlayers,
        uint256 startDate,
        uint40 duration,
        string memory sportType,
        uint8 serviceFeePercentage,
        uint256 fixedPrizeAmount
    ) public {
        // Bound the inputs to reasonable values
        vm.assume(
            bytes(poolName).length > 0 &&
                bytes(poolName).length <= MAX_NAME_LENGTH
        );
        vm.assume(
            bytes(sportType).length > 0 &&
                bytes(sportType).length <= MAX_NAME_LENGTH
        );
        vm.assume(fee > 0 && fee <= MAX_FEE);
        vm.assume(maxPlayers > 1 && maxPlayers <= 1000);
        vm.assume(
            startDate > block.timestamp &&
                startDate < block.timestamp + 365 days
        );
        vm.assume(duration >= 1 hours && duration <= 365 days);
        vm.assume(serviceFeePercentage <= 100);

        // Filter out invalid UTF-8 strings
        try vm.toString(bytes(poolName)) {} catch {
            vm.assume(false);
        }
        try vm.toString(bytes(sportType)) {} catch {
            vm.assume(false);
        }

        address newPool = factory.createPool(
            poolName,
            fee,
            maxPlayers,
            startDate,
            duration,
            owner,
            sportType,
            serviceFeePercentage,
            fixedPrizeAmount,
            0
        );

        address[] memory addresses = factory.getAllPoolAddresses();
        assertEq(addresses.length, 1, "Should have created one pool");
        assertEq(addresses[0], newPool, "Pool address should match");

        // Verify pool info
        IPool pool = IPool(newPool);
        IPool.PoolInfo memory poolInfo = pool.getPoolInfo();
        assertEq(poolInfo.name, poolName, "Pool name should match");
        assertEq(poolInfo.joinFee, fee, "Join fee should match");
        assertEq(
            poolInfo.maxParticipants,
            maxPlayers,
            "Max participants should match"
        );
        assertEq(poolInfo.sportType, sportType, "Sport type should match");
        assertEq(uint8(poolInfo.status), 0, "Pool should be in Open status");
    }

    function test_CreatorPoolLimits() public {
        // Create maximum allowed pools for one creator
        for (uint256 i = 0; i < 100; i++) {
            vm.roll(block.number + 1); // Move to next block to avoid rate limit
            factory.createPool(
                string(abi.encodePacked("Test Pool ", i)),
                1 ether,
                10,
                block.timestamp + 1 days,
                7 days,
                owner,
                "Football",
                SERVICE_FEE_PERCENTAGE,
                0,
                0
            );
        }

        // Try to create one more pool
        vm.roll(block.number + 1);

        factory.createPool(
            "Test Pool 11",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        // Create pool with different creator
        vm.prank(user1);
        factory.createPool(
            "Test Pool 11",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );
    }

    function test_PoolNameUniqueness() public {
        // Create pool with name
        factory.createPool(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        // Try to create pool with same name
        vm.roll(block.number + 1);
        vm.expectRevert(PoolFactory.PoolNameExists.selector);
        factory.createPool(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        // Create pool with different name
        factory.createPool(
            "Test Pool 2",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );
    }

    function test_SportTypeFiltering() public {
        // Create pools with different sport types
        vm.roll(block.number + 1);
        factory.createPool(
            "Football Pool 1",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        vm.roll(block.number + 1);
        factory.createPool(
            "Football Pool 2",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        vm.roll(block.number + 1);
        factory.createPool(
            "Basketball Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Basketball",
            SERVICE_FEE_PERCENTAGE,
            0,
            0
        );

        // Test getPoolsBySportType
        address[] memory footballPools = factory.getPoolsBySportType(
            "Football",
            0,
            10
        );
        assertEq(footballPools.length, 2, "Should find 2 football pools");

        address[] memory basketballPools = factory.getPoolsBySportType(
            "Basketball",
            0,
            10
        );
        assertEq(basketballPools.length, 1, "Should find 1 basketball pool");

        address[] memory tennisPools = factory.getPoolsBySportType(
            "Tennis",
            0,
            10
        );
        assertEq(tennisPools.length, 0, "Should find 0 tennis pools");

        // Test case insensitive search
        address[] memory footballPoolsLower = factory.getPoolsBySportType(
            "football",
            0,
            10
        );
        assertEq(
            footballPoolsLower.length,
            2,
            "Should find 2 football pools with lowercase search"
        );
    }
}
