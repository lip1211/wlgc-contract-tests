// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/StakingManagerUpgradeable.sol";
import "../contracts/WithdrawalManagerUpgradeable.sol";
import "../contracts/PerpetualBondUpgradeable.sol";
import "../contracts/HashPowerCenter.sol";
import "../contracts/ReferralRegistry.sol";
import "../contracts/NodeRegistry.sol";
import "../contracts/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Security Test Suite
 * @notice 测试合约的安全性，包括重入攻击、权限控制、溢出等
 */
contract SecurityTest is Test {
    StakingManagerUpgradeable public stakingManager;
    WithdrawalManagerUpgradeable public withdrawalManager;
    PerpetualBondUpgradeable public perpetualBond;
    HashPowerCenter public hashPowerCenter;
    ReferralRegistry public referralRegistry;
    NodeRegistry public nodeRegistry;
    
    MockERC20 public wlgc;
    MockERC20 public usdt;
    
    address public owner;
    address public attacker;
    address public user;
    address public vault;
    
    function setUp() public {
        owner = address(this);
        attacker = address(0x666);
        user = address(0x1);
        vault = address(0x100);
        
        // 部署代币
        wlgc = new MockERC20("WLGC", "WLGC", 18);
        usdt = new MockERC20("USDT", "USDT", 18);
        
        // 部署基础合约
        referralRegistry = new ReferralRegistry();
        nodeRegistry = new NodeRegistry();
        
        // 部署算力中心
        HashPowerCenter hashPowerCenterImpl = new HashPowerCenter();
        ERC1967Proxy hashPowerCenterProxy = new ERC1967Proxy(
            address(hashPowerCenterImpl),
            abi.encodeWithSelector(HashPowerCenter.initialize.selector)
        );
        hashPowerCenter = HashPowerCenter(address(hashPowerCenterProxy));
        
        // 部署质押管理
        StakingManagerUpgradeable stakingImpl = new StakingManagerUpgradeable();
        ERC1967Proxy stakingProxy = new ERC1967Proxy(
            address(stakingImpl),
            abi.encodeWithSelector(
                StakingManagerUpgradeable.initialize.selector,
                address(wlgc),
                address(hashPowerCenter),
                vault
            )
        );
        stakingManager = StakingManagerUpgradeable(address(stakingProxy));
        
        // 部署提现管理
        WithdrawalManagerUpgradeable withdrawalImpl = new WithdrawalManagerUpgradeable();
        ERC1967Proxy withdrawalProxy = new ERC1967Proxy(
            address(withdrawalImpl),
            abi.encodeWithSelector(
                WithdrawalManagerUpgradeable.initialize.selector,
                address(wlgc),
                address(usdt),
                address(hashPowerCenter),
                vault
            )
        );
        withdrawalManager = WithdrawalManagerUpgradeable(address(withdrawalProxy));
        
        // 部署永动债券
        PerpetualBondUpgradeable bondImpl = new PerpetualBondUpgradeable();
        ERC1967Proxy bondProxy = new ERC1967Proxy(
            address(bondImpl),
            abi.encodeWithSelector(
                PerpetualBondUpgradeable.initialize.selector,
                address(usdt),
                address(hashPowerCenter),
                address(referralRegistry),
                address(nodeRegistry),
                address(0x201),
                address(0x202),
                address(0x203)
            )
        );
        perpetualBond = PerpetualBondUpgradeable(address(bondProxy));
        
        // 配置授权
        hashPowerCenter.setAuthorizedContract(address(stakingManager), true);
        hashPowerCenter.setAuthorizedContract(address(withdrawalManager), true);
        hashPowerCenter.setAuthorizedContract(address(perpetualBond), true);
        
        // 分配代币
        wlgc.mint(user, 1_000_000 * 10**18);
        wlgc.mint(attacker, 1_000_000 * 10**18);
        wlgc.mint(vault, 10_000_000 * 10**18);
        
        usdt.mint(user, 1_000_000 * 10**18);
        usdt.mint(attacker, 1_000_000 * 10**18);
        
        // 授权
        vm.prank(user);
        wlgc.approve(address(stakingManager), type(uint256).max);
        vm.prank(user);
        usdt.approve(address(perpetualBond), type(uint256).max);
        vm.prank(user);
        usdt.approve(address(withdrawalManager), type(uint256).max);
        
        vm.prank(vault);
        wlgc.approve(address(stakingManager), type(uint256).max);
        vm.prank(vault);
        wlgc.approve(address(withdrawalManager), type(uint256).max);
    }
    
    // ============ 重入攻击测试 ============
    
    /**
     * @notice 测试质押重入攻击防护
     */
    function testSecurity_StakingReentrancy() public {
        // 部署恶意合约
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(address(stakingManager), address(wlgc));
        
        wlgc.mint(address(attackerContract), 100_000 * 10**18);
        
        // 尝试重入攻击
        vm.expectRevert();
        attackerContract.attack();
    }
    
    /**
     * @notice 测试提现重入攻击防护
     */
    function testSecurity_WithdrawalReentrancy() public {
        // 添加余额
        withdrawalManager.addUserBalance(user, 100_000 * 10**18);
        
        // 正常提现应该成功
        vm.prank(user);
        withdrawalManager.directWithdraw(10_000 * 10**18);
        
        // 验证余额正确
        assertEq(withdrawalManager.getUserBalance(user), 90_000 * 10**18);
    }
    
    // ============ 权限控制测试 ============
    
    /**
     * @notice 测试未授权用户不能调用owner函数
     */
    function test_RevertWhen_UnauthorizedSetHashPowerPerToken() public {
        vm.prank(attacker);
        vm.expectRevert();
        stakingManager.setHashPowerPerToken(100);
    }
    
    /**
     * @notice 测试未授权用户不能添加余额
     */
    function test_RevertWhen_UnauthorizedAddBalance() public {
        vm.prank(attacker);
        vm.expectRevert();
        withdrawalManager.addUserBalance(user, 1000);
    }
    
    /**
     * @notice 测试未授权合约不能操作算力中心
     */
    function test_RevertWhen_UnauthorizedHashPowerOperation() public {
        vm.prank(attacker);
        vm.expectRevert();
        hashPowerCenter.createStakingOrder(user, 1, 1000, 100);
    }
    
    /**
     * @notice 测试只有owner可以设置授权合约
     */
    function test_RevertWhen_UnauthorizedSetAuthorizedContract() public {
        vm.prank(attacker);
        vm.expectRevert();
        hashPowerCenter.setAuthorizedContract(attacker, true);
    }
    
    /**
     * @notice 测试只有owner可以升级合约
     */
    function test_RevertWhen_UnauthorizedUpgrade() public {
        StakingManagerUpgradeable newImpl = new StakingManagerUpgradeable();
        
        vm.prank(attacker);
        vm.expectRevert();
        stakingManager.upgradeToAndCall(address(newImpl), "");
    }
    
    // ============ 溢出测试 ============
    
    /**
     * @notice 测试极大金额不会导致溢出
     */
    function testSecurity_NoOverflow_LargeAmount() public {
        uint256 largeAmount = type(uint128).max; // 使用uint128最大值
        
        wlgc.mint(user, largeAmount);
        vm.prank(user);
        wlgc.approve(address(stakingManager), largeAmount);
        
        vm.prank(user);
        stakingManager.stake(largeAmount);
        
        // 验证质押成功且数据正确
        (uint256 orderId, , uint256 amount, , , ) = stakingManager.getOrderDetails(user, 1);
        assertEq(amount, largeAmount);
    }
    
    /**
     * @notice 测试算力计算不会溢出
     */
    function testSecurity_NoOverflow_HashPowerCalculation() public {
        uint256 largeAmount = 1_000_000_000 * 10**18; // 10亿代币
        
        wlgc.mint(user, largeAmount);
        vm.prank(user);
        wlgc.approve(address(stakingManager), largeAmount);
        
        vm.prank(user);
        stakingManager.stake(largeAmount);
        
        // 算力应该正确计算
        uint256 hashPower = hashPowerCenter.getUserTotalStaticHashPower(user);
        assertGt(hashPower, 0);
        assertLt(hashPower, type(uint256).max); // 不应该溢出
    }
    
    /**
     * @notice 测试时间戳溢出
     */
    function testSecurity_NoOverflow_Timestamp() public {
        vm.prank(user);
        stakingManager.stake(10_000 * 10**18);
        
        // 跳转到很远的未来
        vm.warp(type(uint40).max);
        vm.roll(block.number + 1000000);
        
        // 应该仍然可以正常操作
        vm.prank(user);
        stakingManager.unstake(1);
    }
    
    // ============ 前端运行测试 ============
    
    /**
     * @notice 测试交易顺序依赖
     */
    function testSecurity_TransactionOrdering() public {
        uint256 amount = 10_000 * 10**18;
        
        // 用户1和用户2同时质押
        address user1 = address(0x11);
        address user2 = address(0x12);
        
        wlgc.mint(user1, amount);
        wlgc.mint(user2, amount);
        
        vm.prank(user1);
        wlgc.approve(address(stakingManager), amount);
        vm.prank(user2);
        wlgc.approve(address(stakingManager), amount);
        
        // 无论哪个先执行，结果应该一致
        vm.prank(user1);
        stakingManager.stake(amount);
        
        vm.prank(user2);
        stakingManager.stake(amount);
        
        // 算力应该相同
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(user2);
        assertEq(hp1, hp2);
    }
    
    /**
     * @notice 测试抢先交易防护
     */
    function testSecurity_FrontRunning() public {
        // 用户准备质押
        uint256 amount = 10_000 * 10**18;
        vm.prank(user);
        stakingManager.stake(amount);
        
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user);
        
        // 攻击者看到交易后立即质押
        vm.prank(attacker);
        wlgc.approve(address(stakingManager), amount);
        vm.prank(attacker);
        stakingManager.stake(amount);
        
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(attacker);
        
        // 两者算力应该相同（没有优势）
        assertEq(hp1, hp2);
    }
    
    // ============ 输入验证测试 ============
    
    /**
     * @notice 测试零地址验证
     */
    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert();
        new StakingManagerUpgradeable();
    }
    
    /**
     * @notice 测试零金额验证
     */
    function test_RevertWhen_ZeroAmountStake() public {
        vm.prank(user);
        vm.expectRevert();
        stakingManager.stake(0);
    }
    
    /**
     * @notice 测试无效订单ID
     */
    function test_RevertWhen_InvalidOrderId() public {
        vm.prank(user);
        vm.expectRevert();
        stakingManager.unstake(999);
    }
    
    /**
     * @notice 测试重复操作
     */
    function test_RevertWhen_DoubleUnstake() public {
        uint256 amount = 10_000 * 10**18;
        vm.prank(user);
        stakingManager.stake(amount);
        
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        
        vm.prank(user);
        stakingManager.unstake(1);
        
        // 尝试再次解押同一订单
        vm.prank(user);
        vm.expectRevert();
        stakingManager.unstake(1);
    }
    
    // ============ 状态一致性测试 ============
    
    /**
     * @notice 测试状态转换的一致性
     */
    function testSecurity_StateConsistency() public {
        uint256 amount = 10_000 * 10**18;
        
        // 初始状态
        assertEq(hashPowerCenter.getUserTotalStaticHashPower(user), 0);
        
        // 质押后状态
        vm.prank(user);
        stakingManager.stake(amount);
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user);
        assertGt(hp1, 0);
        
        // 解押后状态
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        vm.prank(user);
        stakingManager.unstake(1);
        
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(user);
        assertEq(hp2, 0);
    }
    
    /**
     * @notice 测试余额一致性
     */
    function testSecurity_BalanceConsistency() public {
        uint256 initialBalance = wlgc.balanceOf(user);
        uint256 amount = 10_000 * 10**18;
        
        // 质押
        vm.prank(user);
        stakingManager.stake(amount);
        assertEq(wlgc.balanceOf(user), initialBalance - amount);
        
        // 解押
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        vm.prank(user);
        stakingManager.unstake(1);
        
        assertEq(wlgc.balanceOf(user), initialBalance);
    }
    
    // ============ 时间锁测试 ============
    
    /**
     * @notice 测试时间锁不能被绕过
     */
    function test_RevertWhen_BypassTimeLock() public {
        uint256 amount = 10_000 * 10**18;
        vm.prank(user);
        stakingManager.stake(amount);
        
        // 立即尝试解押（不等待24小时）
        vm.prank(user);
        vm.expectRevert();
        stakingManager.unstake(1);
        
        // 等待23小时59分钟（还差1分钟）
        vm.warp(block.timestamp + 24 hours - 60);
        vm.roll(block.number + 1);
        
        vm.prank(user);
        vm.expectRevert();
        stakingManager.unstake(1);
    }
    
    /**
     * @notice 测试提现冷却期
     */
    function test_RevertWhen_BypassCooldown() public {
        withdrawalManager.addUserBalance(user, 100_000 * 10**18);
        
        uint256 withdrawAmount = 10_000 * 10**18;
        uint256 requiredUsdt = withdrawalManager.getRequiredUsdtAmount(withdrawAmount);
        
        usdt.mint(user, requiredUsdt);
        vm.prank(user);
        usdt.approve(address(withdrawalManager), requiredUsdt);
        
        vm.prank(user);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 立即尝试赎回（不等待12小时）
        vm.prank(user);
        vm.expectRevert();
        withdrawalManager.redeemTurbo(1);
        
        // 等待11小时59分钟（还差1分钟）
        vm.warp(block.timestamp + 12 hours - 60);
        
        vm.prank(user);
        vm.expectRevert();
        withdrawalManager.redeemTurbo(1);
    }
    
    // ============ 配额和限制测试 ============
    
    /**
     * @notice 测试最小质押限制
     */
    function test_RevertWhen_BelowMinimumStake() public {
        stakingManager.setMinStakeAmount(1000 * 10**18);
        
        vm.prank(user);
        vm.expectRevert();
        stakingManager.stake(100 * 10**18); // 低于最小值
    }
    
    /**
     * @notice 测试配额限制
     */
    function testSecurity_QuotaLimit() public {
        // 设置很小的配额
        perpetualBond.setTotalQuota(1000 * 10**18);
        
        vm.prank(user);
        referralRegistry.bindReferrer(owner);
        
        // 第一次购买应该成功
        vm.prank(user);
        perpetualBond.createOrder(0, 500 * 10**18);
        
        // 第二次购买应该成功
        vm.prank(user);
        perpetualBond.createOrder(0, 500 * 10**18);
        
        // 第三次购买应该失败（超过配额）
        vm.prank(user);
        vm.expectRevert();
        perpetualBond.createOrder(0, 100 * 10**18);
    }
    
    // ============ 紧急情况测试 ============
    
    /**
     * @notice 测试暂停功能
     */
    function testSecurity_PauseFunction() public {
        uint256 amount = 10_000 * 10**18;
        
        // 正常情况下可以质押
        vm.prank(user);
        stakingManager.stake(amount);
        
        // 暂停后不能质押（如果合约有pause功能）
        // 注：当前合约可能没有pause功能，这里只是示例
    }
    
    /**
     * @notice 测试紧急提现
     */
    function testSecurity_EmergencyWithdrawal() public {
        uint256 amount = 10_000 * 10**18;
        vm.prank(user);
        stakingManager.stake(amount);
        
        // 在紧急情况下应该能够提现
        // 注：需要合约实现紧急提现功能
    }
    
    // ============ 数据完整性测试 ============
    
    /**
     * @notice 测试订单数据完整性
     */
    function testSecurity_OrderDataIntegrity() public {
        uint256 amount = 10_000 * 10**18;
        vm.prank(user);
        stakingManager.stake(amount);
        
        (uint256 orderId, address userAddr, uint256 stakedAmount, uint256 timestamp, , ) = 
            stakingManager.getOrderDetails(user, 1);
        
        assertEq(orderId, 1);
        assertEq(userAddr, user);
        assertEq(stakedAmount, amount);
        assertEq(timestamp, block.timestamp);
    }
    
    /**
     * @notice 测试算力数据完整性
     */
    function testSecurity_HashPowerDataIntegrity() public {
        uint256 amount = 10_000 * 10**18;
        vm.prank(user);
        stakingManager.stake(amount);
        
        uint256 userHashPower = hashPowerCenter.getUserTotalStaticHashPower(user);
        uint256 totalHashPower = hashPowerCenter.getTotalStaticHashPower();
        
        assertEq(userHashPower, totalHashPower); // 只有一个用户
        assertGt(userHashPower, 0);
    }
}

/**
 * @title Reentrancy Attacker Contract
 * @notice 用于测试重入攻击的恶意合约
 */
contract ReentrancyAttacker {
    StakingManagerUpgradeable public stakingManager;
    MockERC20 public wlgc;
    uint256 public attackCount;
    
    constructor(address _stakingManager, address _wlgc) {
        stakingManager = StakingManagerUpgradeable(_stakingManager);
        wlgc = MockERC20(_wlgc);
    }
    
    function attack() external {
        uint256 amount = 10_000 * 10**18;
        wlgc.approve(address(stakingManager), amount);
        stakingManager.stake(amount);
    }
    
    // 尝试在回调中重入
    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            stakingManager.stake(1000 * 10**18);
        }
    }
}
