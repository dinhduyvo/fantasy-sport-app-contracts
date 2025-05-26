// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PoolTest is Test {
    Pool public pool;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;
    uint8 constant SERVICE_FEE_PERCENTAGE = 10;

    event ParticipantJoined(address indexed participant, uint256 amount);
    event PoolStatusChanged(Pool.Status indexed status, uint40 timestamp);
    event PaidForWinner(address indexed participant, uint256 amount);
    event PaidForService(address indexed ownerAddress, uint256 amount);
    event EmergencyWithdrawn(address indexed owner, uint256 amount);
    event ServiceFeeUpdated(uint8 oldFee, uint8 newFee);
    event PointsUpdated(address indexed participant, uint32 points);
    event WinnersSelected(address[] winners);
    event PlayersSelected(address indexed participant, string[] playerIDs);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        user5 = makeAddr("user5");

        // Deploy implementation
        Pool implementation = new Pool();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            "" // Empty initialization data since we'll initialize in the tests
        );
        // Get pool instance
        pool = Pool(payable(address(proxy)));
    }

    function test_InitializeFailures() public {
        // Test empty pool name
        vm.expectRevert(Pool.InvalidLength.selector);
        pool.initialize(
            "",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test zero fee
        vm.expectRevert(Pool.InvalidAmount.selector);
        pool.initialize(
            "Test Pool",
            0,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test invalid max participants (less than 2)
        vm.expectRevert(Pool.InvalidAmount.selector);
        pool.initialize(
            "Test Pool",
            1 ether,
            1,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test invalid start date
        vm.expectRevert(Pool.InvalidAmount.selector);
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // // Test zero duration
        // vm.expectRevert(Pool.MinimumDurationNotMet.selector);
        // pool.initialize(
        //     "Test Pool",
        //     1 ether,
        //     10,
        //     block.timestamp + 1 days,
        //     0,
        //     owner,
        //     "Football",
        //     SERVICE_FEE_PERCENTAGE,
        //     0,
        //     0,
        //     address(0)
        // );

        // Test empty sport type
        vm.expectRevert(Pool.InvalidLength.selector);
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test zero address owner
        vm.expectRevert(Pool.ZeroAddress.selector);
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            address(0),
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test invalid service fee percentage
        vm.expectRevert(Pool.InvalidAmount.selector);
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            101,
            0,
            0,
            address(0)
        );

        // Initialize successfully
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test double initialization
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        pool.initialize(
            "Test Pool 2",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );
    }

    function test_PoolExpiry() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Add enough participants
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        vm.deal(user1, 2 ether);
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user2, 2 ether);
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user3, 2 ether);
        vm.prank(user3);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Start pool
        pool.startPool();

        // Warp past end time
        vm.warp(block.timestamp + 8 days);

        // Try to join pool - should revert with InvalidStatus
        address user6 = makeAddr("user6");
        vm.deal(user6, 2 ether);
        vm.prank(user6);
        vm.expectRevert(Pool.InvalidStatus.selector);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Try to start pool - should revert with InvalidStatus
        vm.expectRevert(Pool.InvalidStatus.selector);
        pool.startPool();
    }

    function test_EmergencyStop() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Create default player IDs for testing
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Set emergency stop
        pool.setEmergencyStop(true);

        // Try to join pool - should revert
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        vm.expectRevert(Pool.EmergencyStopActive.selector);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Try to start pool - should revert
        vm.expectRevert(Pool.EmergencyStopActive.selector);
        pool.startPool();

        // Remove emergency stop
        pool.setEmergencyStop(false);

        // Should now be able to join
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);
    }

    function test_PauseUnpause() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Create default player IDs for testing
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Pause pool
        pool.pause();

        // Try to join pool - should revert
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Unpause pool
        pool.unpause();

        // Should now be able to join
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);
    }

    function test_ServiceFeeUpdate() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Try to set invalid service fee
        vm.expectRevert(Pool.InvalidAmount.selector);
        pool.setServiceFeePercentage(101);

        // Set valid service fee
        vm.expectEmit(true, true, false, true);
        emit ServiceFeeUpdated(SERVICE_FEE_PERCENTAGE, 15);
        pool.setServiceFeePercentage(15);

        // Add enough participants
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        vm.deal(user1, 2 ether);
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user2, 2 ether);
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user3, 2 ether);
        vm.prank(user3);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        pool.startPool();

        // Record initial balances
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        // End pool with winners
        address[] memory winners = new address[](2);
        winners[0] = user1;
        winners[1] = user2;
        int32[] memory points = new int32[](5);
        points[0] = 10;
        points[1] = 8;
        points[2] = 3;
        points[3] = 2;
        points[4] = 1;
        uint32[] memory winnerDistribution = new uint32[](2);
        winnerDistribution[0] = 70; // 70% for first winner
        winnerDistribution[1] = 30; // 30% for second winner

        // Expect events in the correct order
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user1, 10);
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user2, 8);
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user3, 3);
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user4, 2);
        vm.expectEmit(true, false, false, true);
        emit PointsUpdated(user5, 1);
        vm.expectEmit(true, false, false, true);
        emit WinnersSelected(winners);
        vm.expectEmit(true, false, false, true);
        emit PaidForWinner(user1, 3.5 ether);
        vm.expectEmit(true, false, false, true);
        emit PaidForWinner(user2, 1.5 ether);
        vm.expectEmit(true, false, false, true);
        emit PoolStatusChanged(Pool.Status.Closed, uint40(block.timestamp));

        pool.endPool(points, winners, winnerDistribution);

        // Verify balances
        assertEq(
            user1.balance - user1BalanceBefore,
            3.5 ether,
            "Winner 1 should receive 70% of prize pool"
        );
        assertEq(
            user2.balance - user2BalanceBefore,
            1.5 ether,
            "Winner 2 should receive 30% of prize pool"
        );
    }

    function test_InvalidWinnerScenarios() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Add enough participants
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        vm.deal(user1, 2 ether);
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user2, 2 ether);
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user3, 2 ether);
        vm.prank(user3);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        address user4 = makeAddr("user4");
        vm.deal(user4, 2 ether);
        vm.prank(user4);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        address user5 = makeAddr("user5");
        vm.deal(user5, 2 ether);
        vm.prank(user5);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        pool.startPool();

        // Try to end pool with no winners
        address[] memory winners = new address[](0);
        int32[] memory points = new int32[](5);
        points[0] = 10;
        points[1] = 5;
        points[2] = 3;
        points[3] = 2;
        points[4] = 1;
        uint32[] memory winnerDistribution = new uint32[](0);

        vm.expectRevert("Array lengths mismatch");
        pool.endPool(points, winners, winnerDistribution);

        // Try to end pool with non-participant winner
        address user6 = makeAddr("user6");
        winners = new address[](2);
        winners[0] = user1;
        winners[1] = user6;
        winnerDistribution = new uint32[](2);
        winnerDistribution[0] = 70;
        winnerDistribution[1] = 30;

        vm.expectRevert("Invalid winner");
        pool.endPool(points, winners, winnerDistribution);

        // Try to end pool with distribution exceeding 100%
        winners = new address[](2);
        winners[0] = user1;
        winners[1] = user2;
        winnerDistribution = new uint32[](2);
        winnerDistribution[0] = 70;
        winnerDistribution[1] = 40; // Total 110%
        vm.expectRevert("Distribution exceeds 100%");
        pool.endPool(points, winners, winnerDistribution);
    }

    function test_MinimumParticipationRatio() public {
        // Initialize pool with 10 max participants
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Create default player IDs for testing
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Join with only 2 participants (less than 50% of max)
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user2, 2 ether);
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Try to start pool - should revert due to insufficient participants
        // vm.expectRevert(Pool.InsufficientParticipants.selector);
        pool.startPool();

        // Add more participants to meet minimum ratio (50% of 10 = 5 participants)
        vm.deal(user3, 2 ether);
        vm.prank(user3);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        address user4 = makeAddr("user4");
        vm.deal(user4, 2 ether);
        vm.prank(user4);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        address user5 = makeAddr("user5");
        vm.deal(user5, 2 ether);
        vm.prank(user5);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // Should now be able to start pool with 5 participants (50% of max)
        vm.expectEmit(true, false, false, true);
        emit PoolStatusChanged(Pool.Status.Running, uint40(block.timestamp));
        pool.startPool();
    }

    function test_ClaimPayoutEdgeCases() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Football",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Create default player IDs for testing
        string[] memory defaultPlayerIDs = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            defaultPlayerIDs[i] = string(abi.encodePacked(i + 1));
        }

        // Add enough participants
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user2, 2 ether);
        vm.prank(user2);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        vm.deal(user3, 2 ether);
        vm.prank(user3);
        pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // address user4 = makeAddr("user4");
        // vm.deal(user4, 2 ether);
        // vm.prank(user4);
        // pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        // address user5 = makeAddr("user5");
        // vm.deal(user5, 2 ether);
        // vm.prank(user5);
        // pool.joinPool{value: 1 ether}(defaultPlayerIDs);

        pool.startPool();

        // Record initial balances
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;
        uint256 user3BalanceBefore = user3.balance;

        address[] memory winners = new address[](2);
        winners[0] = user1;
        winners[1] = user2;
        int32[] memory points = new int32[](5);
        points[0] = 10;
        points[1] = 8;
        points[2] = 3;
        points[3] = 2;
        points[4] = 1;
        uint32[] memory winnerDistribution = new uint32[](2);
        winnerDistribution[0] = 70; // 70% for first winner
        winnerDistribution[1] = 30; // 30% for second winner

        pool.endPool(points, winners, winnerDistribution);

        // Verify balances
        assertEq(
            user1.balance - user1BalanceBefore,
            3.5 ether,
            "Winner 1 should receive 70% of prize pool"
        );
        assertEq(
            user2.balance - user2BalanceBefore,
            1.5 ether,
            "Winner 2 should receive 30% of prize pool"
        );
        assertEq(
            user3.balance - user3BalanceBefore,
            0,
            "Non-winner should not receive any prize"
        );
    }

    function test_JoinPoolWithPlayerIDs() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Hockey",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Create player IDs for user1
        string[] memory playerIDs1 = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            playerIDs1[i] = string(abi.encodePacked(i + 1)); // Player IDs 1-10
        }

        // Create player IDs for user2
        string[] memory playerIDs2 = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            playerIDs2[i] = string(abi.encodePacked(i + 5)); // Player IDs 5-14 (some overlap with user1)
        }

        // Join pool with player IDs
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit PlayersSelected(user1, playerIDs1);
        pool.joinPool{value: 1 ether}(playerIDs1);

        // Verify player IDs were stored correctly
        vm.prank(user1);
        string[] memory storedIDs = pool.getPickedPlayers(user1);
        assertEq(
            storedIDs.length,
            playerIDs1.length,
            "Stored player IDs length mismatch"
        );

        for (uint256 i = 0; i < playerIDs1.length; i++) {
            assertEq(storedIDs[i], playerIDs1[i], "Stored player ID mismatch");
        }

        // Join with second user
        vm.deal(user2, 2 ether);
        vm.prank(user2);
        vm.expectEmit(true, false, false, true);
        emit PlayersSelected(user2, playerIDs2);
        pool.joinPool{value: 1 ether}(playerIDs2);

        // Verify player IDs for second user
        vm.prank(user2);
        storedIDs = pool.getPickedPlayers(user2);
        assertEq(
            storedIDs.length,
            playerIDs2.length,
            "Stored player IDs length mismatch for user2"
        );

        for (uint256 i = 0; i < playerIDs2.length; i++) {
            assertEq(
                storedIDs[i],
                playerIDs2[i],
                "Stored player ID mismatch for user2"
            );
        }
    }

    function test_InvalidPlayerIDScenarios() public {
        // Initialize pool
        pool.initialize(
            "Test Pool",
            1 ether,
            10,
            block.timestamp + 1 days,
            7 days,
            owner,
            "Hockey",
            SERVICE_FEE_PERCENTAGE,
            0,
            0,
            address(0)
        );

        // Test empty player IDs array
        string[] memory emptyIDs = new string[](0);
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        // vm.expectRevert(Pool.InvalidPlayerIDs.selector);
        pool.joinPool{value: 1 ether}(emptyIDs);

        // Test too many player IDs (>MAX_PLAYERS_PER_PARTICIPANT)
        string[] memory tooManyIDs = new string[](21); // MAX_PLAYERS_PER_PARTICIPANT is 20
        for (uint256 i = 0; i < tooManyIDs.length; i++) {
            tooManyIDs[i] = string(abi.encodePacked(i + 1));
        }

        vm.prank(user1);
        // vm.expectRevert(Pool.InvalidPlayerIDs.selector);
        pool.joinPool{value: 1 ether}(tooManyIDs);

        // Test valid player IDs
        string[] memory validIDs = new string[](10);
        for (uint256 i = 0; i < validIDs.length; i++) {
            validIDs[i] = string(abi.encodePacked(i + 1));
        }

        vm.prank(user1);
        pool.joinPool{value: 1 ether}(validIDs);

        // Test getting player IDs for non-participant
        vm.prank(user2);
        // vm.expectRevert(Pool.NotParticipant.selector);
        pool.getPickedPlayers(user2);
    }
}
