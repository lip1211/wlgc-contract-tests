// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/HashPowerCenter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title HashPowerCenterTest - 算力中心完整测试套件
 * @notice 测试算力中心的所有功能，包括4种订单类型的管理
 */
contract HashPowerCenterTest is Test {
    HashPowerCenter public hashPowerCenter;
    
    address public owner;
    address public authorizedContract1;
    address public authorizedContract2;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        owner = address(this);
        authorizedContract1 = makeAddr("authorized1");
        authorizedContract2 = makeAddr("authorized2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // 部署HashPowerCenter (UUPS代理模式)
        HashPowerCenter implementation = new HashPowerCenter();
        bytes memory initData = abi.encodeWithSelector(HashPowerCenter.initialize.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        hashPowerCenter = HashPowerCenter(address(proxy));

        // 授权合约
        hashPowerCenter.setAuthorizedContract(authorizedContract1, true);
        hashPowerCenter.setAuthorizedContract(authorizedContract2, true);
    }

    // ============ 初始化测试 ============

    function testInitialization() public view {
        assertEq(hashPowerCenter.owner(), owner);
        assertTrue(hashPowerCenter.authorizedContracts(authorizedContract1));
        assertTrue(hashPowerCenter.authorizedContracts(authorizedContract2));
        
        console.log("=== Initialization Test Passed ===");
    }

    // ============ 质押订单测试 ============

    function testCreateStakingOrder() public {
        uint256 hashPower = 1000 * 10**18;
        
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createStakingOrder(user1, hashPower);
        
        assertEq(orderId, 1);
        assertEq(hashPowerCenter.stakingHashPower(user1), hashPower);
        assertEq(hashPowerCenter.totalStakingHashPower(), hashPower);
        assertEq(hashPowerCenter.getUserStakingOrderCount(user1), 1);
        
        console.log("=== Create Staking Order Test Passed ===");
        console.log("Order ID:", orderId);
        console.log("Hash Power:", hashPower / 10**18);
    }

    function testUpdateStakingOrder() public {
        // 创建订单
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        
        // 更新订单
        uint256 newHashPower = 1500 * 10**18;
        vm.prank(authorizedContract1);
        hashPowerCenter.updateStakingOrder(orderId, newHashPower);
        
        assertEq(hashPowerCenter.stakingHashPower(user1), newHashPower);
        assertEq(hashPowerCenter.totalStakingHashPower(), newHashPower);
        
        console.log("=== Update Staking Order Test Passed ===");
    }

    function testCloseStakingOrder() public {
        // 创建订单
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        
        // 关闭订单
        vm.prank(authorizedContract1);
        hashPowerCenter.closeStakingOrder(orderId);
        
        assertEq(hashPowerCenter.stakingHashPower(user1), 0);
        assertEq(hashPowerCenter.totalStakingHashPower(), 0);
        assertEq(hashPowerCenter.getUserStakingOrderCount(user1), 0);
        
        console.log("=== Close Staking Order Test Passed ===");
    }

    function testMultipleStakingOrders() public {
        // user1创建2个订单
        vm.startPrank(authorizedContract1);
        uint256 orderId1 = hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        uint256 orderId2 = hashPowerCenter.createStakingOrder(user1, 500 * 10**18);
        vm.stopPrank();
        
        assertEq(hashPowerCenter.stakingHashPower(user1), 1500 * 10**18);
        assertEq(hashPowerCenter.getUserStakingOrderCount(user1), 2);
        
        // 关闭第一个订单
        vm.prank(authorizedContract1);
        hashPowerCenter.closeStakingOrder(orderId1);
        
        assertEq(hashPowerCenter.stakingHashPower(user1), 500 * 10**18);
        assertEq(hashPowerCenter.getUserStakingOrderCount(user1), 1);
        
        console.log("=== Multiple Staking Orders Test Passed ===");
    }

    // ============ 债券订单测试 ============

    function testCreateBondOrder() public {
        uint256 hashPower = 2000 * 10**18;
        bool isLongTerm = false;
        uint256 orderId = 0;
        
        vm.prank(authorizedContract1);
        hashPowerCenter.createBondOrder(orderId, user1, hashPower, isLongTerm);
        
        assertEq(hashPowerCenter.bondHashPower(user1), hashPower);
        assertEq(hashPowerCenter.totalBondHashPower(), hashPower);
        assertEq(hashPowerCenter.getUserBondOrderCount(user1), 1);
        
        console.log("=== Create Bond Order Test Passed ===");
    }

    function testCreateLongTermBondOrder() public {
        uint256 hashPower = 3000 * 10**18;
        bool isLongTerm = true;
        uint256 orderId = 0;
        
        vm.prank(authorizedContract1);
        hashPowerCenter.createBondOrder(orderId, user1, hashPower, isLongTerm);
        
        assertEq(hashPowerCenter.bondHashPower(user1), hashPower);
        assertEq(hashPowerCenter.longTermBondHashPower(user1), hashPower);
        assertEq(hashPowerCenter.initialHashPower(user1), hashPower);
        assertEq(hashPowerCenter.totalLongTermBondHashPower(), hashPower);
        assertEq(hashPowerCenter.totalInitialHashPower(), hashPower);
        
        console.log("=== Create Long-Term Bond Order Test Passed ===");
        console.log("Long-term hash power:", hashPower / 10**18);
        console.log("Initial hash power:", hashPower / 10**18);
    }

    function testUpdateBondOrder() public {
        // 创建长期债券订单
        uint256 orderId = 0;
        vm.prank(authorizedContract1);
        hashPowerCenter.createBondOrder(orderId, user1, 2000 * 10**18, true);
        
        // 更新订单（增加算力）
        uint256 newHashPower = 3000 * 10**18;
        vm.prank(authorizedContract1);
        hashPowerCenter.updateBondOrder(orderId, newHashPower);
        
        assertEq(hashPowerCenter.bondHashPower(user1), newHashPower);
        assertEq(hashPowerCenter.longTermBondHashPower(user1), newHashPower);
        // 初始算力不会因为更新而改变（只在创建时增加）
        assertEq(hashPowerCenter.initialHashPower(user1), 2000 * 10**18);
        
        console.log("=== Update Bond Order Test Passed ===");
    }

    function testCloseBondOrder() public {
        // 创建长期债券订单
        uint256 orderId = 0;
        vm.prank(authorizedContract1);
        hashPowerCenter.createBondOrder(orderId, user1, 2000 * 10**18, true);
        
        // 关闭订单
        vm.prank(authorizedContract1);
        hashPowerCenter.closeBondOrder(orderId);
        
        assertEq(hashPowerCenter.bondHashPower(user1), 0);
        assertEq(hashPowerCenter.longTermBondHashPower(user1), 0);
        // 注意：初始算力不会减少
        assertEq(hashPowerCenter.initialHashPower(user1), 2000 * 10**18);
        
        console.log("=== Close Bond Order Test Passed ===");
    }

    // ============ 权益债券订单测试 ============

    function testCreateEquityOrder() public {
        uint256 hashPower = 500 * 10**18;
        
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createEquityOrder(user1, hashPower);
        
        assertEq(orderId, 1);
        assertEq(hashPowerCenter.equityHashPower(user1), hashPower);
        assertEq(hashPowerCenter.totalEquityHashPower(), hashPower);
        assertEq(hashPowerCenter.getUserEquityOrderCount(user1), 1);
        
        console.log("=== Create Equity Order Test Passed ===");
    }

    function testUpdateEquityOrder() public {
        // 创建订单
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createEquityOrder(user1, 500 * 10**18);
        
        // 更新订单
        uint256 newHashPower = 800 * 10**18;
        vm.prank(authorizedContract1);
        hashPowerCenter.updateEquityOrder(orderId, newHashPower);
        
        assertEq(hashPowerCenter.equityHashPower(user1), newHashPower);
        
        console.log("=== Update Equity Order Test Passed ===");
    }

    function testCloseEquityOrder() public {
        // 创建订单
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createEquityOrder(user1, 500 * 10**18);
        
        // 关闭订单
        vm.prank(authorizedContract1);
        hashPowerCenter.closeEquityOrder(orderId);
        
        assertEq(hashPowerCenter.equityHashPower(user1), 0);
        assertEq(hashPowerCenter.getUserEquityOrderCount(user1), 0);
        
        console.log("=== Close Equity Order Test Passed ===");
    }

    // ============ 涡轮订单测试 ============

    function testCreateTurboOrder() public {
        uint256 amount = 100 * 10**18;
        
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createTurboOrder(user1, amount);
        
        assertEq(orderId, 1);
        assertEq(hashPowerCenter.getUserTurboOrderCount(user1), 1);
        
        console.log("=== Create Turbo Order Test Passed ===");
    }

    function testCloseTurboOrder() public {
        // 创建订单
        vm.prank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createTurboOrder(user1, 100 * 10**18);
        
        // 关闭订单
        vm.prank(authorizedContract1);
        hashPowerCenter.closeTurboOrder(orderId);
        
        assertEq(hashPowerCenter.getUserTurboOrderCount(user1), 0);
        
        console.log("=== Close Turbo Order Test Passed ===");
    }

    // ============ 综合算力测试 ============

    function testTotalHashPower() public {
        // 创建各种订单
        vm.startPrank(authorizedContract1);
        hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        hashPowerCenter.createBondOrder(1, user1, 2000 * 10**18, false);
        hashPowerCenter.createEquityOrder(user1, 500 * 10**18);
        vm.stopPrank();
        
        // 验证总算力
        uint256 totalHashPower = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertEq(totalHashPower, 3500 * 10**18);
        
        console.log("=== Total Hash Power Test Passed ===");
        console.log("Total hash power:", totalHashPower / 10**18);
    }

    function testTotalHashPowerWithLongTermBonus() public {
        // 创建长期债券订单（有初始算力）
        vm.prank(authorizedContract1);
        hashPowerCenter.createBondOrder(0, user1, 2000 * 10**18, true);
        
        // 静态算力 = 债券算力 = 2000
        uint256 staticHashPower = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertEq(staticHashPower, 2000 * 10**18);
        
        // 长期算力 = 2000
        assertEq(hashPowerCenter.longTermBondHashPower(user1), 2000 * 10**18);
        
        // 初始算力 = 2000
        assertEq(hashPowerCenter.initialHashPower(user1), 2000 * 10**18);
        
        console.log("=== Total Hash Power With Long-Term Bonus Test Passed ===");
        console.log("Static hash power:", staticHashPower / 10**18);
    }

    function testMultipleUsersHashPower() public {
        // user1
        vm.startPrank(authorizedContract1);
        hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        hashPowerCenter.createBondOrder(1, user1, 2000 * 10**18, false);
        
        // user2
        hashPowerCenter.createStakingOrder(user2, 500 * 10**18);
        hashPowerCenter.createEquityOrder(user2, 300 * 10**18);
        
        // user3
        hashPowerCenter.createBondOrder(2, user3, 1500 * 10**18, true);
        vm.stopPrank();
        
        // 验证各用户算力
        assertEq(hashPowerCenter.getUserTotalStaticHashPower(user1), 3000 * 10**18);
        assertEq(hashPowerCenter.getUserTotalStaticHashPower(user2), 800 * 10**18);
        assertEq(hashPowerCenter.getUserTotalStaticHashPower(user3), 1500 * 10**18);
        
        // 验证全网算力
        assertEq(hashPowerCenter.totalStakingHashPower(), 1500 * 10**18);
        assertEq(hashPowerCenter.totalBondHashPower(), 3500 * 10**18);
        assertEq(hashPowerCenter.totalEquityHashPower(), 300 * 10**18);
        assertEq(hashPowerCenter.totalLongTermBondHashPower(), 1500 * 10**18);
        
        console.log("=== Multiple Users Hash Power Test Passed ===");
        console.log("User1 total:", hashPowerCenter.getUserTotalStaticHashPower(user1) / 10**18);
        console.log("User2 total:", hashPowerCenter.getUserTotalStaticHashPower(user2) / 10**18);
        console.log("User3 total:", hashPowerCenter.getUserTotalStaticHashPower(user3) / 10**18);
    }

    // ============ 社区算力测试 ============

    function testBatchUpdateCommunityHashPower() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        uint256[] memory powers = new uint256[](3);
        powers[0] = 1000 * 10**18;
        powers[1] = 2000 * 10**18;
        powers[2] = 1500 * 10**18;
        
        hashPowerCenter.batchUpdateCommunityHashPower(users, powers);
        
        assertEq(hashPowerCenter.communityHashPower(user1), 1000 * 10**18);
        assertEq(hashPowerCenter.communityHashPower(user2), 2000 * 10**18);
        assertEq(hashPowerCenter.communityHashPower(user3), 1500 * 10**18);
        assertEq(hashPowerCenter.totalCommunityHashPower(), 4500 * 10**18);
        
        console.log("=== Batch Update Community Hash Power Test Passed ===");
    }

    // ============ 权限测试 ============

    function testOnlyAuthorizedCanCreateOrder() public {
        vm.prank(user1);
        vm.expectRevert("Not authorized");
        hashPowerCenter.createStakingOrder(user2, 1000 * 10**18);
        
        console.log("=== Only Authorized Can Create Order Test Passed ===");
    }

    function testOnlyOwnerCanSetAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        hashPowerCenter.setAuthorizedContract(user2, true);
        
        console.log("=== Only Owner Can Set Authorized Test Passed ===");
    }

    function testOnlyOwnerCanBatchUpdateCommunity() public {
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory powers = new uint256[](1);
        powers[0] = 1000 * 10**18;
        
        vm.prank(user1);
        vm.expectRevert();
        hashPowerCenter.batchUpdateCommunityHashPower(users, powers);
        
        console.log("=== Only Owner Can Batch Update Community Test Passed ===");
    }

    // ============ 错误情况测试 ============

    function testCannotCreateOrderForZeroAddress() public {
        vm.prank(authorizedContract1);
        vm.expectRevert("Invalid user");
        hashPowerCenter.createStakingOrder(address(0), 1000 * 10**18);
        
        console.log("=== Cannot Create Order For Zero Address Test Passed ===");
    }

    function testCannotUpdateNonexistentOrder() public {
        vm.prank(authorizedContract1);
        vm.expectRevert("Order not found");
        hashPowerCenter.updateStakingOrder(999, 1000 * 10**18);
        
        console.log("=== Cannot Update Nonexistent Order Test Passed ===");
    }

    function testCannotCloseInactiveOrder() public {
        // 创建并关闭订单
        vm.startPrank(authorizedContract1);
        uint256 orderId = hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        hashPowerCenter.closeStakingOrder(orderId);
        
        // 尝试再次关闭
        vm.expectRevert("Order not active");
        hashPowerCenter.closeStakingOrder(orderId);
        vm.stopPrank();
        
        console.log("=== Cannot Close Inactive Order Test Passed ===");
    }

    // ============ 查询功能测试 ============

    function testGetUserOrders() public {
        // 创建多个订单
        vm.startPrank(authorizedContract1);
        hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        hashPowerCenter.createStakingOrder(user1, 500 * 10**18);
        hashPowerCenter.createStakingOrder(user1, 800 * 10**18);
        vm.stopPrank();
        
        // 查询订单列表
        uint256[] memory orderIds = hashPowerCenter.getUserStakingOrders(user1, 0, 10);
        assertEq(orderIds.length, 3);
        assertEq(orderIds[0], 1);
        assertEq(orderIds[1], 2);
        assertEq(orderIds[2], 3);
        
        console.log("=== Get User Orders Test Passed ===");
    }

    function testGetUserOrdersWithPagination() public {
        // 创建5个订单
        vm.startPrank(authorizedContract1);
        for (uint256 i = 0; i < 5; i++) {
            hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        }
        vm.stopPrank();
        
        // 分页查询
        uint256[] memory page1 = hashPowerCenter.getUserStakingOrders(user1, 0, 2);
        assertEq(page1.length, 2);
        
        uint256[] memory page2 = hashPowerCenter.getUserStakingOrders(user1, 2, 2);
        assertEq(page2.length, 2);
        
        uint256[] memory page3 = hashPowerCenter.getUserStakingOrders(user1, 4, 2);
        assertEq(page3.length, 1);
        
        console.log("=== Get User Orders With Pagination Test Passed ===");
    }

    function testGetHashPowerDetails() public {
        // 创建各种订单
        vm.startPrank(authorizedContract1);
        hashPowerCenter.createStakingOrder(user1, 1000 * 10**18);
        hashPowerCenter.createBondOrder(1, user1, 2000 * 10**18, true);
        hashPowerCenter.createEquityOrder(user1, 500 * 10**18);
        vm.stopPrank();
        
        // 查询详细信息
        (
            uint256 totalHashPower,
            uint256 stakingPower,
            uint256 bondPower,
            uint256 equityPower,
            uint256 initialPower,
            uint256 consensusPower,
            uint256 communityPower
        ) = hashPowerCenter.getUserHashPowerDetails(user1);
        
        assertEq(totalHashPower, 3500 * 10**18);
        assertEq(stakingPower, 1000 * 10**18);
        assertEq(bondPower, 2000 * 10**18);
        assertEq(equityPower, 500 * 10**18);
        assertEq(initialPower, 2000 * 10**18);
        assertEq(communityPower, 0);
        
        console.log("=== Get Hash Power Details Test Passed ===");
        console.log("Total:", totalHashPower / 10**18);
        console.log("Staking:", stakingPower / 10**18);
        console.log("Bond:", bondPower / 10**18);
        console.log("Equity:", equityPower / 10**18);
    }
}
