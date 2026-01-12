// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PerpetualBondUpgradeable.sol";
import "../contracts/MockERC20.sol";
// MockWlgcToken will be defined inline
import "../contracts/ReferralRegistry.sol";
import "../contracts/NodeRegistry.sol";
import "../contracts/HashPowerCenter.sol";
import "../contracts/WithdrawalManagerUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock WlgcToken
contract MockWlgcToken {
    string public name = "WLGC Token";
    string public symbol = "WLGC";
    uint8 public decimals = 18;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 public totalSupply;
    uint256 private currentPrice;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function initialize(uint256 _initialPrice) external {
        currentPrice = _initialPrice;
    }
    
    function getCurrentPriceE18() external view returns (uint256) {
        return currentPrice;
    }
    
    function setPrice(uint256 _price) external {
        currentPrice = _price;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}

// Mock PerpetualPool
contract MockPerpetualPool {
    MockWlgcToken public wlgc;
    
    constructor(address _wlgc) {
        wlgc = MockWlgcToken(_wlgc);
    }
    
    function transferToWithdrawal(address to, uint256 amount) external {
        wlgc.mint(to, amount);
    }
}

contract PerpetualBondTest is Test {
    PerpetualBondUpgradeable public perpetualBond;
    MockERC20 public usdt;
    MockWlgcToken public wlgc;
    ReferralRegistry public referralRegistry;
    NodeRegistry public nodeRegistry;
    HashPowerCenter public hashPowerCenter;
    WithdrawalManagerUpgradeable public withdrawalManager;
    MockPerpetualPool public perpetualPool;
    
    address public owner;
    address public user1;
    address public user2;
    address public referrer;
    address public rewardDistributor;
    
    address public communityAddress;
    address public marketValueContract;
    address public floorPriceContract;
    address public blackHole;
    
    uint256 constant INITIAL_PRICE = 1 * 10**18; // 1 USDT per WLGC
    uint256 constant SINGLE_TOKEN_POWER = 1 * 10**18; // 1 power per token
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        referrer = address(0x3);
        rewardDistributor = address(0x4);
        
        communityAddress = address(0x10);
        marketValueContract = address(0x11);
        floorPriceContract = address(0x12);
        blackHole = address(0x13);
        
        // 部署代币
        usdt = new MockERC20("USDT", "USDT", 18);
        wlgc = new MockWlgcToken();
        wlgc.initialize(INITIAL_PRICE);
        
        // 部署推荐和节点合约
        referralRegistry = new ReferralRegistry();
        nodeRegistry = new NodeRegistry();
        
        // 部署算力中心（可升级）
        HashPowerCenter hashPowerCenterImpl = new HashPowerCenter();
        bytes memory hashPowerInitData = abi.encodeWithSelector(
            HashPowerCenter.initialize.selector
        );
        ERC1967Proxy hashPowerProxy = new ERC1967Proxy(
            address(hashPowerCenterImpl),
            hashPowerInitData
        );
        hashPowerCenter = HashPowerCenter(address(hashPowerProxy));
        
        // 部署提现管理（可升级）
        WithdrawalManagerUpgradeable withdrawalManagerImpl = new WithdrawalManagerUpgradeable();
        bytes memory withdrawalInitData = abi.encodeWithSelector(
            WithdrawalManagerUpgradeable.initialize.selector,
            address(wlgc),
            address(usdt),
            INITIAL_PRICE
        );
        ERC1967Proxy withdrawalProxy = new ERC1967Proxy(
            address(withdrawalManagerImpl),
            withdrawalInitData
        );
        withdrawalManager = WithdrawalManagerUpgradeable(address(withdrawalProxy));
        
        // 部署永动池
        perpetualPool = new MockPerpetualPool(address(wlgc));
        
        // 部署PerpetualBond（可升级）
        PerpetualBondUpgradeable perpetualBondImpl = new PerpetualBondUpgradeable();
        bytes memory perpetualBondInitData = abi.encodeWithSelector(
            PerpetualBondUpgradeable.initialize.selector,
            address(usdt),
            address(wlgc),
            SINGLE_TOKEN_POWER
        );
        ERC1967Proxy perpetualBondProxy = new ERC1967Proxy(
            address(perpetualBondImpl),
            perpetualBondInitData
        );
        perpetualBond = PerpetualBondUpgradeable(address(perpetualBondProxy));
        
        // 配置PerpetualBond
        perpetualBond.setPerpetualPool(address(perpetualPool));
        perpetualBond.setWithdrawalManager(address(withdrawalManager));
        perpetualBond.setReferralRegistry(address(referralRegistry));
        perpetualBond.setNodeRegistry(address(nodeRegistry));
        perpetualBond.setHashPowerCenter(address(hashPowerCenter));
        perpetualBond.setCommunityAddress(communityAddress);
        perpetualBond.setMarketValueContract(marketValueContract);
        perpetualBond.setFloorPriceContract(floorPriceContract);
        perpetualBond.setBlackHole(blackHole);
        perpetualBond.setStakeEnabled(true);
        perpetualBond.setRewardDistributorAuthorization(rewardDistributor, true);
        
        // 配置算力中心授权
        hashPowerCenter.setAuthorizedContract(address(perpetualBond), true);
        
        // 配置提现管理授权
        withdrawalManager.setRewardContractAuthorization(address(perpetualBond), true);
        withdrawalManager.setWithdrawalEnabled(true);
        
        // 绑定推荐关系
        vm.prank(referrer);
        referralRegistry.setInvite(owner);
        
        vm.prank(user1);
        referralRegistry.setInvite(referrer);
        
        vm.prank(user2);
        referralRegistry.setInvite(referrer);
        
        // 给用户分配代币
        usdt.mint(user1, 1000000 * 10**18);
        usdt.mint(user2, 1000000 * 10**18);
        wlgc.mint(address(perpetualPool), 10000000 * 10**18);
        wlgc.mint(rewardDistributor, 1000000 * 10**18);
        
        // 授权
        vm.prank(user1);
        usdt.approve(address(perpetualBond), type(uint256).max);
        
        vm.prank(user2);
        usdt.approve(address(perpetualBond), type(uint256).max);
        
        vm.prank(rewardDistributor);
        wlgc.approve(address(perpetualBond), type(uint256).max);
    }
    
    // ============ 初始化测试 ============
    
    function testInitialization() public {
        assertEq(address(perpetualBond.USDT()), address(usdt));
        assertEq(address(perpetualBond.WLGC()), address(wlgc));
        assertEq(perpetualBond.singleTokenPower(), SINGLE_TOKEN_POWER);
        assertTrue(perpetualBond.stakeEnabled());
    }
    
    function testPeriodConfigs() public {
        // 30天: 98折, 1.05倍
        (uint256 days0, uint256 discount0, uint256 multiplier0, bool active0) = perpetualBond.periodConfigs(0);
        assertEq(days0, 30);
        assertEq(discount0, 98);
        assertEq(multiplier0, 105);
        assertTrue(active0);
        
        // 90天: 95折, 1.10倍
        (uint256 days1, uint256 discount1, uint256 multiplier1, bool active1) = perpetualBond.periodConfigs(1);
        assertEq(days1, 90);
        assertEq(discount1, 95);
        assertEq(multiplier1, 110);
        assertTrue(active1);
        
        // 180天: 92折, 1.20倍
        (uint256 days2, uint256 discount2, uint256 multiplier2, bool active2) = perpetualBond.periodConfigs(2);
        assertEq(days2, 180);
        assertEq(discount2, 92);
        assertEq(multiplier2, 120);
        assertTrue(active2);
        
        // 360天: 88折, 1.30倍
        (uint256 days3, uint256 discount3, uint256 multiplier3, bool active3) = perpetualBond.periodConfigs(3);
        assertEq(days3, 360);
        assertEq(discount3, 88);
        assertEq(multiplier3, 130);
        assertTrue(active3);
        
        // 540天: 85折, 1.40倍
        (uint256 days4, uint256 discount4, uint256 multiplier4, bool active4) = perpetualBond.periodConfigs(4);
        assertEq(days4, 540);
        assertEq(discount4, 85);
        assertEq(multiplier4, 140);
        assertTrue(active4);
    }
    
    // ============ 创建订单测试 ============
    
    function testCreateOrder30Days() public {
        uint256 inputValue = 100 * 10**18; // 100 USDT
        uint256 expectedPayment = (inputValue * 98) / 100; // 98 USDT
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE; // 100 tokens
        
        uint256 user1UsdtBefore = usdt.balanceOf(user1);
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        // 验证USDT支付
        assertEq(user1UsdtBefore - usdt.balanceOf(user1), expectedPayment);
        
        // 验证订单
        (
            uint256 orderId,
            address user,
            uint256 periodType,
            uint256 usdtPaid,
            uint256 tokenAmount,
            uint256 tokenPrice,
            uint256 createTime,
            uint256 endTime,
            uint256 claimedPrincipal,
            uint256 pendingRewards,
            uint256 claimedRewards,
            uint256 initialPowerValue
        ) = perpetualBond.orders(1);
        
        assertEq(orderId, 1);
        assertEq(user, user1);
        assertEq(periodType, 0);
        assertEq(usdtPaid, expectedPayment);
        assertEq(tokenAmount, expectedTokens);
        assertEq(tokenPrice, INITIAL_PRICE);
        assertEq(createTime, block.timestamp);
        assertEq(endTime, block.timestamp + 30 days);
        assertEq(claimedPrincipal, 0);
        assertEq(pendingRewards, 0);
        assertEq(claimedRewards, 0);
        assertEq(initialPowerValue, 0); // 30天没有初始算力
    }
    
    function testCreateOrder90Days() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedPayment = (inputValue * 95) / 100; // 95 USDT
        
        vm.prank(user1);
        perpetualBond.createOrder(1, inputValue);
        
        (,,,,,,,,,,, uint256 initialPowerValue) = perpetualBond.orders(1);
        assertEq(initialPowerValue, 0); // 90天没有初始算力
    }
    
    function testCreateOrder180Days() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedPayment = (inputValue * 92) / 100; // 92 USDT
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE; // 100 tokens
        uint256 expectedPower = (expectedTokens * 120 * SINGLE_TOKEN_POWER) / (100 * 10**18);
        
        vm.prank(user1);
        perpetualBond.createOrder(2, inputValue);
        
        (,,,,,,,,,,, uint256 initialPowerValue) = perpetualBond.orders(1);
        assertEq(initialPowerValue, expectedPower); // 180天有初始算力
    }
    
    function testCreateOrder360Days() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedPayment = (inputValue * 88) / 100; // 88 USDT
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE;
        uint256 expectedPower = (expectedTokens * 130 * SINGLE_TOKEN_POWER) / (100 * 10**18);
        
        vm.prank(user1);
        perpetualBond.createOrder(3, inputValue);
        
        (,,,,,,,,,,, uint256 initialPowerValue) = perpetualBond.orders(1);
        assertEq(initialPowerValue, expectedPower); // 360天有初始算力
    }
    
    function testCreateOrder540Days() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedPayment = (inputValue * 85) / 100; // 85 USDT
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE;
        uint256 expectedPower = (expectedTokens * 140 * SINGLE_TOKEN_POWER) / (100 * 10**18);
        
        vm.prank(user1);
        perpetualBond.createOrder(4, inputValue);
        
        (,,,,,,,,,,, uint256 initialPowerValue) = perpetualBond.orders(1);
        assertEq(initialPowerValue, expectedPower); // 540天有初始算力
    }
    
    function testMultipleOrders() public {
        uint256 inputValue = 100 * 10**18;
        
        vm.startPrank(user1);
        perpetualBond.createOrder(0, inputValue);
        perpetualBond.createOrder(1, inputValue);
        perpetualBond.createOrder(2, inputValue);
        vm.stopPrank();
        
        uint256[] memory orders = perpetualBond.getUserOrders(user1);
        assertEq(orders.length, 3);
        assertEq(orders[0], 1);
        assertEq(orders[1], 2);
        assertEq(orders[2], 3);
    }
    
    // ============ 本金领取测试 ============
    
    function testClaimPrincipalAfter15Days() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE; // 100 tokens
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue); // 30天周期
        
        // 快进15天（50%时间）
        vm.warp(block.timestamp + 15 days);
        
        uint256 claimable = perpetualBond.getClaimablePrincipal(1);
        uint256 expectedClaimable = expectedTokens / 2; // 50%
        assertApproxEqRel(claimable, expectedClaimable, 0.01e18); // 1%误差
        
        vm.prank(user1);
        perpetualBond.claimPrincipal(1, claimable);
        
        (,,,,,,,uint256 claimedPrincipal,,,,) = perpetualBond.orders(1);
        assertEq(claimedPrincipal, claimable);
    }
    
    function testClaimPrincipalAfterEnd() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE;
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        // 快进30天（100%时间）
        vm.warp(block.timestamp + 30 days);
        
        uint256 claimable = perpetualBond.getClaimablePrincipal(1);
        assertEq(claimable, expectedTokens); // 100%
        
        vm.prank(user1);
        perpetualBond.claimPrincipal(1, claimable);
        
        (,,,,,,,uint256 claimedPrincipal,,,,) = perpetualBond.orders(1);
        assertEq(claimedPrincipal, expectedTokens);
    }
    
    function testClaimPrincipalMultipleTimes() public {
        uint256 inputValue = 100 * 10**18;
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE;
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        // 第一次领取（10天后，33.3%）
        vm.warp(block.timestamp + 10 days);
        uint256 claimable1 = perpetualBond.getClaimablePrincipal(1);
        vm.prank(user1);
        perpetualBond.claimPrincipal(1, claimable1);
        
        // 第二次领取（20天后，66.6%）
        vm.warp(block.timestamp + 10 days);
        uint256 claimable2 = perpetualBond.getClaimablePrincipal(1);
        vm.prank(user1);
        perpetualBond.claimPrincipal(1, claimable2);
        
        // 第三次领取（30天后，100%）
        vm.warp(block.timestamp + 10 days);
        uint256 claimable3 = perpetualBond.getClaimablePrincipal(1);
        vm.prank(user1);
        perpetualBond.claimPrincipal(1, claimable3);
        
        (,,,,,,,uint256 claimedPrincipal,,,,) = perpetualBond.orders(1);
        assertApproxEqRel(claimedPrincipal, expectedTokens, 0.01e18);
    }
    
    // ============ 利息测试 ============
    
    function testAddOrderRewards() public {
        uint256 inputValue = 100 * 10**18;
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        uint256 rewardAmount = 10 * 10**18; // 10 tokens
        
        vm.prank(rewardDistributor);
        perpetualBond.addOrderRewards(1, rewardAmount);
        
        (,,,,,,,, uint256 pendingRewards,,,) = perpetualBond.orders(1);
        assertEq(pendingRewards, rewardAmount);
    }
    
    function testClaimRewards() public {
        uint256 inputValue = 100 * 10**18;
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        uint256 rewardAmount = 10 * 10**18;
        
        vm.prank(rewardDistributor);
        perpetualBond.addOrderRewards(1, rewardAmount);
        
        uint256 user1WlgcBefore = wlgc.balanceOf(user1);
        
        vm.prank(user1);
        perpetualBond.claimRewards(1, rewardAmount);
        
        assertEq(wlgc.balanceOf(user1) - user1WlgcBefore, rewardAmount);
        
        (,,,,,,,,, uint256 claimedRewards,,) = perpetualBond.orders(1);
        assertEq(claimedRewards, rewardAmount);
    }
    
    function testMultipleRewards() public {
        uint256 inputValue = 100 * 10**18;
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        // 添加第一次利息
        vm.prank(rewardDistributor);
        perpetualBond.addOrderRewards(1, 10 * 10**18);
        
        // 添加第二次利息
        vm.prank(rewardDistributor);
        perpetualBond.addOrderRewards(1, 5 * 10**18);
        
        (,,,,,,,, uint256 pendingRewards,,,) = perpetualBond.orders(1);
        assertEq(pendingRewards, 15 * 10**18);
        
        // 领取部分利息
        vm.prank(user1);
        perpetualBond.claimRewards(1, 8 * 10**18);
        
        (,,,,,,,, uint256 pendingRewards2, uint256 claimedRewards,,) = perpetualBond.orders(1);
        assertEq(pendingRewards2, 7 * 10**18);
        assertEq(claimedRewards, 8 * 10**18);
    }
    
    // ============ 算力测试 ============
    
    function testHashPowerIntegration() public {
        uint256 inputValue = 100 * 10**18;
        
        vm.prank(user1);
        perpetualBond.createOrder(2, inputValue); // 180天，有初始算力
        
        // 验证算力中心记录
        uint256 userPower = hashPowerCenter.getUserTotalStaticHashPower(user1);
        assertTrue(userPower > 0);
    }
    
    // ============ 配置管理测试 ============
    
    function testSetPeriodConfig() public {
        perpetualBond.setPeriodConfig(5, 720, 80, 150, true);
        
        (uint256 days5, uint256 discount5, uint256 multiplier5, bool active5) = perpetualBond.periodConfigs(5);
        assertEq(days5, 720);
        assertEq(discount5, 80);
        assertEq(multiplier5, 150);
        assertTrue(active5);
    }
    
    function testUpdateSingleTokenPower() public {
        uint256 newPower = 2 * 10**18;
        perpetualBond.updateSingleTokenPower(newPower);
        assertEq(perpetualBond.singleTokenPower(), newPower);
    }
    
    function testSetStakeEnabled() public {
        perpetualBond.setStakeEnabled(false);
        assertFalse(perpetualBond.stakeEnabled());
        
        perpetualBond.setStakeEnabled(true);
        assertTrue(perpetualBond.stakeEnabled());
    }
    
    function testSetTotalQuota() public {
        uint256 quota = 1000000 * 10**18;
        perpetualBond.setTotalQuota(quota);
        assertEq(perpetualBond.totalQuota(), quota);
    }
    
    function testSetRewardDistributorAuthorization() public {
        address newDistributor = address(0x99);
        perpetualBond.setRewardDistributorAuthorization(newDistributor, true);
        assertTrue(perpetualBond.authorizedRewardDistributors(newDistributor));
        
        perpetualBond.setRewardDistributorAuthorization(newDistributor, false);
        assertFalse(perpetualBond.authorizedRewardDistributors(newDistributor));
    }
    
    // ============ 错误处理测试 ============
    
    function test_RevertWhen_CreateOrderWithoutReferral() public {
        address noReferralUser = address(0x999);
        usdt.mint(noReferralUser, 1000 * 10**18);
        
        vm.startPrank(noReferralUser);
        usdt.approve(address(perpetualBond), type(uint256).max);
        
        vm.expectRevert("Must bind referral");
        perpetualBond.createOrder(0, 100 * 10**18);
        vm.stopPrank();
    }
    
    function test_RevertWhen_CreateOrderBelowMinimum() public {
        vm.prank(user1);
        vm.expectRevert("Below min stake amount");
        perpetualBond.createOrder(0, 50 * 10**18); // 最低100
    }
    
    function test_RevertWhen_CreateOrderExceedsQuota() public {
        perpetualBond.setTotalQuota(150 * 10**18);
        
        vm.prank(user1);
        vm.expectRevert("Quota exceeded");
        perpetualBond.createOrder(0, 200 * 10**18);
    }
    
    function test_RevertWhen_CreateOrderWhenDisabled() public {
        perpetualBond.setStakeEnabled(false);
        
        vm.prank(user1);
        vm.expectRevert("PerpetualBond: staking not enabled");
        perpetualBond.createOrder(0, 100 * 10**18);
    }
    
    function test_RevertWhen_ClaimPrincipalNotOwner() public {
        vm.prank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        
        vm.warp(block.timestamp + 15 days);
        
        vm.prank(user2);
        vm.expectRevert("Not owner");
        perpetualBond.claimPrincipal(1, 1 * 10**18);
    }
    
    function test_RevertWhen_ClaimPrincipalTooMuch() public {
        vm.prank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        
        vm.warp(block.timestamp + 15 days);
        
        uint256 claimable = perpetualBond.getClaimablePrincipal(1);
        
        vm.prank(user1);
        vm.expectRevert("Insufficient claimable principal");
        perpetualBond.claimPrincipal(1, claimable + 1);
    }
    
    function test_RevertWhen_ClaimRewardsNotOwner() public {
        vm.prank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        
        vm.prank(rewardDistributor);
        perpetualBond.addOrderRewards(1, 10 * 10**18);
        
        vm.prank(user2);
        vm.expectRevert("Not owner");
        perpetualBond.claimRewards(1, 1 * 10**18);
    }
    
    function test_RevertWhen_ClaimRewardsTooMuch() public {
        vm.prank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        
        vm.prank(rewardDistributor);
        perpetualBond.addOrderRewards(1, 10 * 10**18);
        
        vm.prank(user1);
        vm.expectRevert("Insufficient rewards");
        perpetualBond.claimRewards(1, 11 * 10**18);
    }
    
    function test_RevertWhen_AddRewardsUnauthorized() public {
        vm.prank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        
        vm.prank(user2);
        vm.expectRevert("PerpetualBond: not authorized");
        perpetualBond.addOrderRewards(1, 10 * 10**18);
    }
    
    function test_RevertWhen_OnlyOwnerCanSetConfig() public {
        vm.prank(user1);
        vm.expectRevert();
        perpetualBond.setPeriodConfig(0, 30, 98, 105, true);
        
        vm.prank(user1);
        vm.expectRevert();
        perpetualBond.updateSingleTokenPower(2 * 10**18);
        
        vm.prank(user1);
        vm.expectRevert();
        perpetualBond.setStakeEnabled(false);
    }
    
    // ============ 查询功能测试 ============
    
    function testGetUserOrders() public {
        vm.startPrank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        perpetualBond.createOrder(1, 200 * 10**18);
        perpetualBond.createOrder(2, 300 * 10**18);
        vm.stopPrank();
        
        uint256[] memory orders = perpetualBond.getUserOrders(user1);
        assertEq(orders.length, 3);
    }
    
    function testGetClaimablePrincipal() public {
        uint256 inputValue = 100 * 10**18;
        
        vm.prank(user1);
        perpetualBond.createOrder(0, inputValue);
        
        // 时间0%
        uint256 claimable0 = perpetualBond.getClaimablePrincipal(1);
        assertEq(claimable0, 0);
        
        // 时间25%
        vm.warp(block.timestamp + 7.5 days);
        uint256 claimable25 = perpetualBond.getClaimablePrincipal(1);
        assertTrue(claimable25 > 0);
        
        // 时间50%
        vm.warp(block.timestamp + 7.5 days);
        uint256 claimable50 = perpetualBond.getClaimablePrincipal(1);
        assertTrue(claimable50 > claimable25);
        
        // 时间100%
        vm.warp(block.timestamp + 15 days);
        uint256 claimable100 = perpetualBond.getClaimablePrincipal(1);
        uint256 expectedTokens = (inputValue * 10**18) / INITIAL_PRICE;
        assertEq(claimable100, expectedTokens);
    }
    
    function testGetGlobalStats() public {
        vm.prank(user1);
        perpetualBond.createOrder(0, 100 * 10**18);
        
        vm.prank(user2);
        perpetualBond.createOrder(1, 200 * 10**18);
        
        assertEq(perpetualBond.usedQuota(), 300 * 10**18);
    }
}
