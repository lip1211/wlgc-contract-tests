// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/StakingManagerUpgradeable.sol";
import "../contracts/HashPowerCenter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock WLGC Token
contract MockWLGC is ERC20 {
    uint256 private currentPrice;
    
    constructor() ERC20("WLGC Token", "WLGC") {
        _mint(msg.sender, 10000000 * 10**18);
        currentPrice = 1 * 10**18; // 初始价格1 USDT
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setCurrentPrice(uint256 price) external {
        currentPrice = price;
    }
    
    function getCurrentPriceE18() external view returns (uint256) {
        return currentPrice;
    }
}

/**
 * @title StakingManagerTest - 质押管理完整测试套件
 */
contract StakingManagerTest is Test {
    StakingManagerUpgradeable public stakingManager;
    HashPowerCenter public hashPowerCenter;
    MockWLGC public wlgc;
    
    address public owner;
    address public stakingVault;
    address public withdrawalContract;
    address public user1;
    address public user2;
    
    uint256 public constant BASE_TOKEN_PRICE = 1 * 10**18; // 1 USDT
    uint256 public constant MIN_STAKING_AMOUNT = 1 * 10**18; // 1 WLGC

    function setUp() public {
        owner = address(this);
        stakingVault = makeAddr("stakingVault");
        withdrawalContract = makeAddr("withdrawalContract");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 部署Mock WLGC
        wlgc = new MockWLGC();

        // 部署HashPowerCenter (UUPS代理)
        HashPowerCenter hpcImpl = new HashPowerCenter();
        bytes memory hpcInitData = abi.encodeWithSelector(HashPowerCenter.initialize.selector);
        ERC1967Proxy hpcProxy = new ERC1967Proxy(address(hpcImpl), hpcInitData);
        hashPowerCenter = HashPowerCenter(address(hpcProxy));

        // 部署StakingManager (UUPS代理)
        StakingManagerUpgradeable smImpl = new StakingManagerUpgradeable();
        bytes memory smInitData = abi.encodeWithSelector(
            StakingManagerUpgradeable.initialize.selector,
            address(wlgc),
            address(hashPowerCenter),
            BASE_TOKEN_PRICE
        );
        ERC1967Proxy smProxy = new ERC1967Proxy(address(smImpl), smInitData);
        stakingManager = StakingManagerUpgradeable(address(smProxy));

        // 授权StakingManager到HashPowerCenter
        hashPowerCenter.setAuthorizedContract(address(stakingManager), true);

        // 配置StakingManager
        stakingManager.setStakingVault(stakingVault);
        stakingManager.setWithdrawalContract(withdrawalContract);
        stakingManager.setStakingEnabled(true);

        // 给用户分配代币
        wlgc.mint(user1, 10000 * 10**18);
        wlgc.mint(user2, 10000 * 10**18);
        
        // 给vault和withdrawal合约分配代币
        wlgc.mint(stakingVault, 100000 * 10**18);
        wlgc.mint(withdrawalContract, 100000 * 10**18);
    }

    // ============ 初始化测试 ============

    function testInitialization() public view {
        assertEq(address(stakingManager.WLGC()), address(wlgc));
        assertEq(address(stakingManager.hashPowerCenter()), address(hashPowerCenter));
        assertEq(stakingManager.baseTokenPrice(), BASE_TOKEN_PRICE);
        assertEq(stakingManager.minStakingAmount(), MIN_STAKING_AMOUNT);
        assertEq(stakingManager.minUnstakingTime(), 24 hours);
        assertTrue(stakingManager.stakingEnabled());
        
        console.log("=== Initialization Test Passed ===");
    }

    // ============ 质押测试 ============

    function testStake() public {
        uint256 stakeAmount = 100 * 10**18;
        
        // 用户授权
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), stakeAmount);
        
        // 质押
        stakingManager.stake(stakeAmount);
        vm.stopPrank();
        
        // 验证订单创建
        uint256[] memory orders = stakingManager.getUserOrders(user1);
        assertEq(orders.length, 1);
        assertEq(orders[0], 1);
        
        // 验证订单详情
        (
            uint256 localOrderId,
            uint256 centerOrderId,
            address user,
            uint256 stakedAmount,
            uint256 unclaimedInterest,
            uint256 hashPower,
            ,
            ,
            bool isActive,
        ) = stakingManager.getOrderDetails(1);
        
        assertEq(localOrderId, 1);
        assertEq(centerOrderId, 1);
        assertEq(user, user1);
        assertEq(stakedAmount, stakeAmount);
        assertEq(unclaimedInterest, 0);
        assertEq(hashPower, stakeAmount); // 价格=基础价格时，算力=本金
        assertTrue(isActive);
        
        // 验证统计
        (uint256 totalStaked,,,) = stakingManager.getGlobalStats();
        assertEq(totalStaked, stakeAmount);
        
        // 验证算力中心
        assertEq(hashPowerCenter.stakingHashPower(user1), hashPower);
        
        console.log("=== Stake Test Passed ===");
        console.log("Staked amount:", stakeAmount / 10**18);
        console.log("Hash power:", hashPower / 10**18);
    }

    function testStakeMultipleOrders() public {
        // 用户1质押2次
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 1000 * 10**18);
        stakingManager.stake(100 * 10**18);
        stakingManager.stake(200 * 10**18);
        vm.stopPrank();
        
        // 验证订单数量
        uint256[] memory orders = stakingManager.getUserOrders(user1);
        assertEq(orders.length, 2);
        
        // 验证统计
        (uint256 totalStaked,,,) = stakingManager.getGlobalStats();
        assertEq(totalStaked, 300 * 10**18);
        
        console.log("=== Stake Multiple Orders Test Passed ===");
    }

    function testStakeWithHigherPrice() public {
        // 设置更高的价格
        wlgc.setCurrentPrice(2 * 10**18); // 2 USDT
        
        uint256 stakeAmount = 100 * 10**18;
        
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), stakeAmount);
        stakingManager.stake(stakeAmount);
        vm.stopPrank();
        
        // 计算预期算力
        // 单币算力 = (2 - 1) * 80% + 1 = 0.8 + 1 = 1.8
        // 订单算力 = 100 * 1.8 = 180
        uint256 expectedPowerPerToken = ((2 * 10**18 - BASE_TOKEN_PRICE) * 8000 / 10000) + 1 * 10**18;
        uint256 expectedHashPower = stakeAmount * expectedPowerPerToken / 10**18;
        
        (,,,,,uint256 hashPower,,,,) = stakingManager.getOrderDetails(1);
        assertEq(hashPower, expectedHashPower);
        
        console.log("=== Stake With Higher Price Test Passed ===");
        console.log("Price: 2");
        console.log("Power per token:", expectedPowerPerToken / 10**18, "WLGC");
        console.log("Total hash power:", hashPower / 10**18, "units");
    }

    function test_RevertWhen_StakeBelowMinimum() public {
        uint256 lowAmount = 0.5 * 10**18; // 低于最低质押量
        
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), lowAmount);
        vm.expectRevert("Staking: amount too low");
        stakingManager.stake(lowAmount);
        vm.stopPrank();
        
        console.log("=== Stake Below Minimum Test Passed ===");
    }

    function test_RevertWhen_StakeWhenDisabled() public {
        // 关闭质押
        stakingManager.setStakingEnabled(false);
        
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        vm.expectRevert("Staking: staking not enabled");
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        console.log("=== Stake When Disabled Test Passed ===");
    }

    // ============ 解押测试 ============

    function testUnstake() public {
        // 先质押
        uint256 stakeAmount = 100 * 10**18;
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), stakeAmount);
        stakingManager.stake(stakeAmount);
        vm.stopPrank();
        
        // vault授权
        vm.prank(stakingVault);
        wlgc.approve(address(stakingManager), stakeAmount);
        
        // 快进24小时
        vm.warp(block.timestamp + 24 hours + 1);
        
        // 解押
        vm.prank(user1);
        stakingManager.unstake(1);
        
        // 验证订单状态
        (,,,,,,,,bool isActive,) = stakingManager.getOrderDetails(1);
        assertFalse(isActive);
        
        // 验证统计
        (uint256 totalStaked, uint256 totalStakedAcc, uint256 totalUnstaked,) = stakingManager.getGlobalStats();
        assertEq(totalStaked, 0);
        assertEq(totalStakedAcc, stakeAmount);
        assertEq(totalUnstaked, stakeAmount);
        
        // 验证算力中心
        assertEq(hashPowerCenter.stakingHashPower(user1), 0);
        
        console.log("=== Unstake Test Passed ===");
    }

    function test_RevertWhen_UnstakeBeforeTime() public {
        // 先质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        
        // 立即尝试解押（未到24小时）
        vm.expectRevert("Staking: unstaking time not reached");
        stakingManager.unstake(1);
        vm.stopPrank();
        
        console.log("=== Unstake Before Time Test Passed ===");
    }

    function test_RevertWhen_UnstakeNotOwner() public {
        // user1质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        // 快进24小时
        vm.warp(block.timestamp + 24 hours + 1);
        
        // user2尝试解押user1的订单
        vm.prank(user2);
        vm.expectRevert("Staking: not order owner");
        stakingManager.unstake(1);
        
        console.log("=== Unstake Not Owner Test Passed ===");
    }

    function testCanUnstake() public {
        // 质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        // 检查是否可以解押（未到时间）
        (bool can, string memory reason) = stakingManager.canUnstake(1);
        assertFalse(can);
        assertEq(reason, "Unstaking time not reached");
        
        // 快进24小时
        vm.warp(block.timestamp + 24 hours + 1);
        
        // 再次检查
        (can, reason) = stakingManager.canUnstake(1);
        assertTrue(can);
        assertEq(reason, "Can unstake");
        
        console.log("=== Can Unstake Test Passed ===");
    }

    // ============ 利息测试 ============

    function testAddInterest() public {
        // 质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        // 添加利息
        uint256 interest = 10 * 10**18;
        stakingManager.addInterest(1, interest);
        
        // 验证利息
        (,,,,uint256 unclaimedInterest, uint256 hashPower,,,,) = stakingManager.getOrderDetails(1);
        assertEq(unclaimedInterest, interest);
        
        // 验证算力更新（本金+利息）
        uint256 expectedHashPower = (100 * 10**18 + interest);
        assertEq(hashPower, expectedHashPower);
        
        console.log("=== Add Interest Test Passed ===");
        console.log("Interest:", interest / 10**18);
        console.log("New hash power:", hashPower / 10**18);
    }

    function testBatchAddInterest() public {
        // 创建2个质押订单
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 300 * 10**18);
        stakingManager.stake(100 * 10**18);
        stakingManager.stake(200 * 10**18);
        vm.stopPrank();
        
        // 批量添加利息
        uint256[] memory orderIds = new uint256[](2);
        orderIds[0] = 1;
        orderIds[1] = 2;
        
        uint256[] memory interests = new uint256[](2);
        interests[0] = 10 * 10**18;
        interests[1] = 20 * 10**18;
        
        stakingManager.batchAddInterest(orderIds, interests);
        
        // 验证
        (,,,,uint256 interest1,,,,,) = stakingManager.getOrderDetails(1);
        (,,,,uint256 interest2,,,,,) = stakingManager.getOrderDetails(2);
        
        assertEq(interest1, 10 * 10**18);
        assertEq(interest2, 20 * 10**18);
        
        console.log("=== Batch Add Interest Test Passed ===");
    }

    function testClaimInterest() public {
        // 质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        // 添加利息
        uint256 interest = 10 * 10**18;
        stakingManager.addInterest(1, interest);
        
        // 授权withdrawal合约转账
        vm.prank(withdrawalContract);
        wlgc.approve(address(stakingManager), interest);
        
        // 领取利息
        vm.prank(user1);
        stakingManager.claimInterest(1);
        
        // 验证利息已清零
        (,,,,uint256 unclaimedInterest,,,,,) = stakingManager.getOrderDetails(1);
        assertEq(unclaimedInterest, 0);
        
        // 验证统计
        (,,,uint256 totalInterestClaimed) = stakingManager.getGlobalStats();
        assertEq(totalInterestClaimed, interest);
        
        console.log("=== Claim Interest Test Passed ===");
    }

    function test_RevertWhen_ClaimInterestNoInterest() public {
        // 质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        
        // 尝试领取利息（没有利息）
        vm.expectRevert("Staking: no interest to claim");
        stakingManager.claimInterest(1);
        vm.stopPrank();
        
        console.log("=== Claim Interest No Interest Test Passed ===");
    }

    // ============ 算力计算测试 ============

    function testHashPowerCalculation() public {
        // 测试不同价格下的算力计算
        
        // 价格 = 基础价格
        wlgc.setCurrentPrice(1 * 10**18);
        uint256 powerPerToken1 = stakingManager.getCurrentPowerPerToken();
        assertEq(powerPerToken1, 1 * 10**18);
        
        // 价格 = 2 * 基础价格
        wlgc.setCurrentPrice(2 * 10**18);
        uint256 powerPerToken2 = stakingManager.getCurrentPowerPerToken();
        // (2 - 1) * 80% + 1 = 1.8
        assertEq(powerPerToken2, 1.8 * 10**18);
        
        // 价格 = 3 * 基础价格
        wlgc.setCurrentPrice(3 * 10**18);
        uint256 powerPerToken3 = stakingManager.getCurrentPowerPerToken();
        // (3 - 1) * 80% + 1 = 2.6
        assertEq(powerPerToken3, 2.6 * 10**18);
        
        console.log("=== Hash Power Calculation Test Passed ===");
        console.log("Power at 1x price:", powerPerToken1 / 10**18, "WLGC");
        console.log("Power at 2x price:", powerPerToken2 / 10**18, "WLGC");
        console.log("Power at 3x price:", powerPerToken3 / 10**18, "WLGC");
    }

    function testHashPowerWithInterest() public {
        // 质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        // 初始算力
        uint256 initialHashPower = stakingManager.getOrderHashPower(1);
        assertEq(initialHashPower, 100 * 10**18);
        
        // 添加利息
        stakingManager.addInterest(1, 20 * 10**18);
        
        // 算力应该增加（本金+利息）
        uint256 newHashPower = stakingManager.getOrderHashPower(1);
        assertEq(newHashPower, 120 * 10**18);
        
        console.log("=== Hash Power With Interest Test Passed ===");
        console.log("Initial power:", initialHashPower / 10**18);
        console.log("Power after interest:", newHashPower / 10**18);
    }

    // ============ 配置测试 ============

    function testSetMinStakingAmount() public {
        uint256 newMin = 10 * 10**18;
        stakingManager.setMinStakingAmount(newMin);
        assertEq(stakingManager.minStakingAmount(), newMin);
        
        console.log("=== Set Min Staking Amount Test Passed ===");
    }

    function testSetMinUnstakingTime() public {
        uint256 newTime = 48 hours;
        stakingManager.setMinUnstakingTime(newTime);
        assertEq(stakingManager.minUnstakingTime(), newTime);
        
        console.log("=== Set Min Unstaking Time Test Passed ===");
    }

    function testSetStakingEnabled() public {
        stakingManager.setStakingEnabled(false);
        assertFalse(stakingManager.stakingEnabled());
        
        stakingManager.setStakingEnabled(true);
        assertTrue(stakingManager.stakingEnabled());
        
        console.log("=== Set Staking Enabled Test Passed ===");
    }

    // ============ 查询功能测试 ============

    function testGetUserTotalHashPower() public {
        // 创建多个订单
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 500 * 10**18);
        stakingManager.stake(100 * 10**18);
        stakingManager.stake(200 * 10**18);
        vm.stopPrank();
        
        // 查询总算力
        uint256 totalPower = stakingManager.getUserTotalHashPower(user1);
        assertEq(totalPower, 300 * 10**18);
        
        console.log("=== Get User Total Hash Power Test Passed ===");
        console.log("Total power:", totalPower / 10**18);
    }

    function testGetGlobalStats() public {
        // 多个用户质押
        vm.startPrank(user1);
        wlgc.approve(address(stakingManager), 100 * 10**18);
        stakingManager.stake(100 * 10**18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        wlgc.approve(address(stakingManager), 200 * 10**18);
        stakingManager.stake(200 * 10**18);
        vm.stopPrank();
        
        // 查询统计
        (
            uint256 totalStaked,
            uint256 totalStakedAcc,
            uint256 totalUnstaked,
            uint256 totalInterestClaimed
        ) = stakingManager.getGlobalStats();
        
        assertEq(totalStaked, 300 * 10**18);
        assertEq(totalStakedAcc, 300 * 10**18);
        assertEq(totalUnstaked, 0);
        assertEq(totalInterestClaimed, 0);
        
        console.log("=== Get Global Stats Test Passed ===");
        console.log("Total staked:", totalStaked / 10**18);
    }

    // ============ 权限测试 ============

    function test_RevertWhen_OnlyOwnerCanSetConfig() public {
        vm.prank(user1);
        vm.expectRevert();
        stakingManager.setMinStakingAmount(10 * 10**18);
        
        console.log("=== Only Owner Can Set Config Test Passed ===");
    }

    function test_RevertWhen_OnlyOwnerCanAddInterest() public {
        vm.prank(user1);
        vm.expectRevert();
        stakingManager.addInterest(1, 10 * 10**18);
        
        console.log("=== Only Owner Can Add Interest Test Passed ===");
    }
}
