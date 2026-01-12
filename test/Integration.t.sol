// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PresaleUpgradeable.sol";
import "../contracts/HashPowerCenter.sol";
import "../contracts/StakingManagerUpgradeable.sol";
import "../contracts/WithdrawalManagerUpgradeable.sol";
import "../contracts/PerpetualBondUpgradeable.sol";
import "../contracts/ReferralRegistry.sol";
import "../contracts/NodeRegistry.sol";
import "../contracts/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Integration Test Suite
 * @notice 测试合约间的集成和完整用户流程
 */
contract IntegrationTest is Test {
    // 核心合约
    PresaleUpgradeable public presale;
    HashPowerCenter public hashPowerCenter;
    StakingManagerUpgradeable public stakingManager;
    WithdrawalManagerUpgradeable public withdrawalManager;
    PerpetualBondUpgradeable public perpetualBond;
    ReferralRegistry public referralRegistry;
    NodeRegistry public nodeRegistry;
    
    // 代币
    MockERC20 public usdt;
    MockERC20 public usd1;
    MockERC20 public wlgc;
    
    // 地址
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public vault;
    address public communityReceiver;
    address public marketCapReceiver;
    address public bottomPoolReceiver;
    
    // 常量
    uint256 constant INITIAL_USDT = 1_000_000 * 10**18;
    uint256 constant INITIAL_WLGC = 10_000_000 * 10**18;
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        vault = address(0x100);
        communityReceiver = address(0x101);
        marketCapReceiver = address(0x102);
        bottomPoolReceiver = address(0x103);
        
        // 部署代币
        usdt = new MockERC20("USDT", "USDT", 18);
        usd1 = new MockERC20("USD1", "USD1", 18);
        wlgc = new MockERC20("WLGC", "WLGC", 18);
        
        // 部署基础合约
        referralRegistry = new ReferralRegistry();
        nodeRegistry = new NodeRegistry();
        
        // 部署算力中心（可升级）
        HashPowerCenter hashPowerCenterImpl = new HashPowerCenter();
        ERC1967Proxy hashPowerCenterProxy = new ERC1967Proxy(
            address(hashPowerCenterImpl),
            abi.encodeWithSelector(HashPowerCenter.initialize.selector)
        );
        hashPowerCenter = HashPowerCenter(address(hashPowerCenterProxy));
        
        // 部署预售合约（可升级）
        PresaleUpgradeable presaleImpl = new PresaleUpgradeable();
        ERC1967Proxy presaleProxy = new ERC1967Proxy(
            address(presaleImpl),
            abi.encodeWithSelector(
                PresaleUpgradeable.initialize.selector,
                address(usdt),
                address(usd1),
                address(referralRegistry),
                address(nodeRegistry),
                1 * 10**18 // baseTokenPrice
            )
        );
        presale = PresaleUpgradeable(address(presaleProxy));
        
        // 部署质押管理（可升级）
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
        
        // 部署提现管理（可升级）
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
        
        // 部署永动债券（可升级）
        PerpetualBondUpgradeable bondImpl = new PerpetualBondUpgradeable();
        ERC1967Proxy bondProxy = new ERC1967Proxy(
            address(bondImpl),
            abi.encodeWithSelector(
                PerpetualBondUpgradeable.initialize.selector,
                address(usdt),
                address(hashPowerCenter),
                address(referralRegistry),
                address(nodeRegistry),
                communityReceiver,
                marketCapReceiver,
                bottomPoolReceiver
            )
        );
        perpetualBond = PerpetualBondUpgradeable(address(bondProxy));
        
        // 配置授权
        hashPowerCenter.setAuthorizedContract(address(stakingManager), true);
        hashPowerCenter.setAuthorizedContract(address(withdrawalManager), true);
        hashPowerCenter.setAuthorizedContract(address(perpetualBond), true);
        
        // 配置预售
        presale.setPresaleActive(true);
        
        // 给用户分配代币
        usdt.mint(user1, INITIAL_USDT);
        usdt.mint(user2, INITIAL_USDT);
        usdt.mint(user3, INITIAL_USDT);
        
        wlgc.mint(user1, INITIAL_WLGC);
        wlgc.mint(user2, INITIAL_WLGC);
        wlgc.mint(user3, INITIAL_WLGC);
        wlgc.mint(vault, INITIAL_WLGC * 10);
        
        // 授权
        vm.prank(user1);
        usdt.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        usdt.approve(address(perpetualBond), type(uint256).max);
        vm.prank(user1);
        wlgc.approve(address(stakingManager), type(uint256).max);
        
        vm.prank(user2);
        usdt.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        usdt.approve(address(perpetualBond), type(uint256).max);
        vm.prank(user2);
        wlgc.approve(address(stakingManager), type(uint256).max);
        
        vm.prank(user3);
        usdt.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        usdt.approve(address(perpetualBond), type(uint256).max);
        vm.prank(user3);
        wlgc.approve(address(stakingManager), type(uint256).max);
        
        vm.prank(vault);
        wlgc.approve(address(stakingManager), type(uint256).max);
        vm.prank(vault);
        wlgc.approve(address(withdrawalManager), type(uint256).max);
    }
    
    // ============ 完整用户流程测试 ============
    
    /**
     * @notice 测试完整流程：预售 → 质押 → 提现
     */
    function testFullFlow_Presale_Staking_Withdrawal() public {
        // 1. 用户1绑定推荐人（owner）
        vm.prank(user1);
        referralRegistry.bindReferrer(owner);
        
        // 2. 用户1购买社区节点（1000 USDT）
        vm.prank(user1);
        presale.buyNode(0, address(usdt)); // 社区节点
        
        // 验证节点购买
        assertTrue(nodeRegistry.hasNode(user1));
        
        // 3. 用户1质押WLGC
        uint256 stakeAmount = 10_000 * 10**18;
        vm.prank(user1);
        stakingManager.stake(stakeAmount);
        
        // 验证质押
        (uint256 orderId, , uint256 amount, , , ) = stakingManager.getOrderDetails(user1, 1);
        assertEq(orderId, 1);
        assertEq(amount, stakeAmount);
        
        // 验证算力增加
        uint256 userHashPower = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertGt(userHashPower, 0);
        
        // 4. 等待24小时后解押
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        stakingManager.unstake(1);
        
        // 5. 添加提现余额
        withdrawalManager.addUserBalance(user1, stakeAmount);
        
        // 6. 直接提现
        uint256 withdrawAmount = 5_000 * 10**18;
        vm.prank(user1);
        withdrawalManager.directWithdraw(withdrawAmount);
        
        // 验证提现成功
        assertEq(wlgc.balanceOf(user1), INITIAL_WLGC - stakeAmount + withdrawAmount);
    }
    
    /**
     * @notice 测试完整流程：预售 → 债券 → 本金领取
     */
    function testFullFlow_Presale_Bond_Principal() public {
        // 1. 建立推荐关系：user1 → user2 → user3
        vm.prank(user2);
        referralRegistry.bindReferrer(user1);
        
        vm.prank(user3);
        referralRegistry.bindReferrer(user2);
        
        // 2. user3购买超级节点（5000 USDT）
        vm.prank(user3);
        presale.buyNode(1, address(usdt)); // 超级节点
        
        // 3. user3购买180天债券（10000 USDT）
        uint256 bondAmount = 10_000 * 10**18;
        vm.prank(user3);
        perpetualBond.createOrder(2, bondAmount); // 180天周期
        
        // 验证债券创建
        (uint256 orderId, , , , , , , ) = perpetualBond.getOrderDetails(user3, 1);
        assertEq(orderId, 1);
        
        // 验证算力增加（180天有初始算力）
        uint256 userHashPower = hashPowerCenter.getUserTotalStaticHashPower(user3);
        assertGt(userHashPower, 0);
        
        // 4. 等待90天后领取50%本金
        vm.warp(block.timestamp + 90 days);
        
        uint256 claimAmount = bondAmount / 2;
        vm.prank(user3);
        perpetualBond.claimPrincipal(1, claimAmount);
        
        // 验证本金领取
        assertGt(wlgc.balanceOf(user3), INITIAL_WLGC);
    }
    
    /**
     * @notice 测试涡轮提现完整流程
     */
    function testFullFlow_TurboWithdrawal() public {
        // 1. 添加用户余额
        uint256 balance = 100_000 * 10**18;
        withdrawalManager.addUserBalance(user1, balance);
        
        // 2. 请求涡轮提现
        uint256 withdrawAmount = 10_000 * 10**18;
        uint256 requiredUsdt = withdrawalManager.getRequiredUsdtAmount(withdrawAmount);
        
        usdt.mint(user1, requiredUsdt);
        vm.prank(user1);
        usdt.approve(address(withdrawalManager), requiredUsdt);
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 验证涡轮订单创建
        assertTrue(withdrawalManager.hasTurboOrder(user1, 1));
        
        // 3. 等待12小时后赎回
        vm.warp(block.timestamp + 12 hours + 1);
        
        uint256 wlgcBefore = wlgc.balanceOf(user1);
        vm.prank(user1);
        withdrawalManager.redeemTurbo(1);
        
        // 验证赎回成功（80%到账）
        uint256 expectedAmount = (withdrawAmount * 80) / 100;
        assertEq(wlgc.balanceOf(user1) - wlgcBefore, expectedAmount);
    }
    
    // ============ 跨合约交互测试 ============
    
    /**
     * @notice 测试多个合约同时操作算力
     */
    function testCrossContract_HashPowerSync() public {
        // 1. 质押增加算力
        uint256 stakeAmount = 10_000 * 10**18;
        vm.prank(user1);
        stakingManager.stake(stakeAmount);
        
        uint256 hashPower1 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertGt(hashPower1, 0);
        
        // 2. 购买债券增加算力
        vm.prank(user1);
        referralRegistry.bindReferrer(owner);
        
        uint256 bondAmount = 10_000 * 10**18;
        vm.prank(user1);
        perpetualBond.createOrder(2, bondAmount); // 180天
        
        uint256 hashPower2 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertGt(hashPower2, hashPower1); // 算力应该增加
        
        // 3. 解押减少算力
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        stakingManager.unstake(1);
        
        uint256 hashPower3 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertLt(hashPower3, hashPower2); // 算力应该减少
    }
    
    /**
     * @notice 测试推荐关系在多个合约中的一致性
     */
    function testCrossContract_ReferralConsistency() public {
        // 建立推荐链：owner → user1 → user2 → user3
        vm.prank(user1);
        referralRegistry.bindReferrer(owner);
        
        vm.prank(user2);
        referralRegistry.bindReferrer(user1);
        
        vm.prank(user3);
        referralRegistry.bindReferrer(user2);
        
        // 验证推荐链
        assertEq(referralRegistry.getReferrer(user1), owner);
        assertEq(referralRegistry.getReferrer(user2), user1);
        assertEq(referralRegistry.getReferrer(user3), user2);
        
        // 在预售中使用推荐关系
        vm.prank(user3);
        presale.buyNode(0, address(usdt));
        
        // 在债券中使用推荐关系
        vm.prank(user3);
        perpetualBond.createOrder(0, 1_000 * 10**18);
        
        // 推荐关系应该保持一致
        assertEq(referralRegistry.getReferrer(user3), user2);
    }
    
    /**
     * @notice 测试节点状态在多个合约中的一致性
     */
    function testCrossContract_NodeConsistency() public {
        vm.prank(user1);
        referralRegistry.bindReferrer(owner);
        
        // 在预售中购买节点
        vm.prank(user1);
        presale.buyNode(1, address(usdt)); // 超级节点
        
        // 验证节点状态
        assertTrue(nodeRegistry.hasNode(user1));
        assertEq(nodeRegistry.getNodeType(user1), 1);
        
        // 在债券合约中应该能识别节点状态
        vm.prank(user1);
        perpetualBond.createOrder(0, 1_000 * 10**18);
        
        // 节点状态应该保持一致
        assertTrue(nodeRegistry.hasNode(user1));
    }
    
    // ============ 并发操作测试 ============
    
    /**
     * @notice 测试多用户并发质押
     */
    function testConcurrent_MultiUserStaking() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        // user1质押
        vm.prank(user1);
        stakingManager.stake(stakeAmount);
        
        // user2质押
        vm.prank(user2);
        stakingManager.stake(stakeAmount);
        
        // user3质押
        vm.prank(user3);
        stakingManager.stake(stakeAmount);
        
        // 验证全网算力
        uint256 totalHashPower = hashPowerCenter.getTotalStaticHashPower();
        assertGt(totalHashPower, 0);
        
        // 验证每个用户的算力
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(user2);
        uint256 hp3 = hashPowerCenter.getUserTotalStaticHashPower(user3);
        
        assertEq(hp1, hp2);
        assertEq(hp2, hp3);
    }
    
    /**
     * @notice 测试多用户并发购买债券
     */
    function testConcurrent_MultiUserBonds() public {
        // 建立推荐关系
        vm.prank(user1);
        referralRegistry.bindReferrer(owner);
        vm.prank(user2);
        referralRegistry.bindReferrer(owner);
        vm.prank(user3);
        referralRegistry.bindReferrer(owner);
        
        uint256 bondAmount = 10_000 * 10**18;
        
        // 三个用户同时购买不同周期的债券
        vm.prank(user1);
        perpetualBond.createOrder(0, bondAmount); // 30天
        
        vm.prank(user2);
        perpetualBond.createOrder(2, bondAmount); // 180天
        
        vm.prank(user3);
        perpetualBond.createOrder(4, bondAmount); // 540天
        
        // 验证算力不同（周期越长算力越高）
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(user2);
        uint256 hp3 = hashPowerCenter.getUserTotalStaticHashPower(user3);
        
        assertLt(hp1, hp2);
        assertLt(hp2, hp3);
    }
    
    // ============ 边界条件测试 ============
    
    /**
     * @notice 测试零金额操作
     */
    function test_RevertWhen_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        stakingManager.stake(0);
    }
    
    /**
     * @notice 测试极大金额操作
     */
    function testBoundary_LargeAmount() public {
        uint256 largeAmount = 1_000_000 * 10**18;
        wlgc.mint(user1, largeAmount);
        
        vm.prank(user1);
        wlgc.approve(address(stakingManager), largeAmount);
        
        vm.prank(user1);
        stakingManager.stake(largeAmount);
        
        // 验证质押成功
        (uint256 orderId, , uint256 amount, , , ) = stakingManager.getOrderDetails(user1, 1);
        assertEq(amount, largeAmount);
    }
    
    /**
     * @notice 测试时间边界
     */
    function testBoundary_TimeEdge() public {
        uint256 stakeAmount = 10_000 * 10**18;
        vm.prank(user1);
        stakingManager.stake(stakeAmount);
        
        // 刚好24小时，应该还不能解押
        vm.warp(block.timestamp + 24 hours);
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        vm.expectRevert();
        stakingManager.unstake(1);
        
        // 超过24小时，应该可以解押
        vm.warp(block.timestamp + 1);
        
        vm.prank(user1);
        stakingManager.unstake(1); // 不应该revert
    }
    
    // ============ 资金流动验证 ============
    
    /**
     * @notice 测试资金流动的完整性
     */
    function testFundFlow_Completeness() public {
        uint256 initialUsdtUser = usdt.balanceOf(user1);
        uint256 initialUsdtPresale = usdt.balanceOf(address(presale));
        
        // 用户购买节点
        vm.prank(user1);
        referralRegistry.bindReferrer(owner);
        
        uint256 nodePrice = 1_000 * 10**18;
        vm.prank(user1);
        presale.buyNode(0, address(usdt));
        
        // 验证资金转移
        assertEq(usdt.balanceOf(user1), initialUsdtUser - nodePrice);
        assertEq(usdt.balanceOf(address(presale)), initialUsdtPresale + nodePrice);
    }
    
    /**
     * @notice 测试WLGC流动的完整性
     */
    function testFundFlow_WlgcCirculation() public {
        uint256 stakeAmount = 10_000 * 10**18;
        
        uint256 initialUser = wlgc.balanceOf(user1);
        uint256 initialVault = wlgc.balanceOf(vault);
        
        // 质押
        vm.prank(user1);
        stakingManager.stake(stakeAmount);
        
        assertEq(wlgc.balanceOf(user1), initialUser - stakeAmount);
        assertEq(wlgc.balanceOf(vault), initialVault + stakeAmount);
        
        // 解押
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        stakingManager.unstake(1);
        
        assertEq(wlgc.balanceOf(user1), initialUser);
        assertEq(wlgc.balanceOf(vault), initialVault);
    }
    
    // ============ 算力一致性验证 ============
    
    /**
     * @notice 测试算力计算的一致性
     */
    function testHashPower_Consistency() public {
        // 质押相同金额
        uint256 amount = 10_000 * 10**18;
        
        vm.prank(user1);
        stakingManager.stake(amount);
        
        vm.prank(user2);
        stakingManager.stake(amount);
        
        // 算力应该相同
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(user2);
        
        assertEq(hp1, hp2);
        
        // 全网算力应该等于两者之和
        uint256 totalHp = hashPowerCenter.getTotalStaticHashPower();
        assertEq(totalHp, hp1 + hp2);
    }
    
    /**
     * @notice 测试算力更新的及时性
     */
    function testHashPower_Timeliness() public {
        uint256 amount = 10_000 * 10**18;
        
        // 初始算力为0
        assertEq(hashPowerCenter.getUserTotalStaticHashPower(user1), 0);
        
        // 质押后立即有算力
        vm.prank(user1);
        stakingManager.stake(amount);
        
        uint256 hp1 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertGt(hp1, 0);
        
        // 解押后立即减少算力
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        stakingManager.unstake(1);
        
        uint256 hp2 = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertEq(hp2, 0);
    }
}
