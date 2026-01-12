// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/WithdrawalManagerUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20代币
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock权益债券合约
contract MockEquityBond {
    uint256 private orderCounter = 1;
    
    event EquityOrderCreated(address indexed user, uint256 indexed orderId, uint256 amount, uint256 price);
    
    function createEquityOrder(address user, uint256 amount, uint256 tokenPrice) 
        external 
        returns (uint256) 
    {
        uint256 orderId = orderCounter++;
        emit EquityOrderCreated(user, orderId, amount, tokenPrice);
        return orderId;
    }
}

contract WithdrawalManagerTest is Test {
    WithdrawalManagerUpgradeable public withdrawalManager;
    MockERC20 public wlgc;
    MockERC20 public usdt;
    MockEquityBond public equityBond;
    
    address public owner;
    address public user1;
    address public user2;
    address public turboVault;
    address public blackHole;
    address public rewardContract;
    
    uint256 constant INITIAL_PRICE = 1 * 10**6; // 1 USDT (精度6位)
    uint256 constant TURBO_COOLDOWN = 12 hours;
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        turboVault = address(0x3);
        blackHole = address(0x4);
        rewardContract = address(0x5);
        
        // 部署代币
        wlgc = new MockERC20("WLGC Token", "WLGC");
        usdt = new MockERC20("USDT Token", "USDT");
        equityBond = new MockEquityBond();
        
        // 部署可升级合约
        WithdrawalManagerUpgradeable impl = new WithdrawalManagerUpgradeable();
        bytes memory initData = abi.encodeWithSelector(
            WithdrawalManagerUpgradeable.initialize.selector,
            address(wlgc),
            address(usdt),
            blackHole,
            INITIAL_PRICE
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        withdrawalManager = WithdrawalManagerUpgradeable(address(proxy));
        
        // 配置
        withdrawalManager.setTurboVault(turboVault);
        withdrawalManager.setEquityBond(address(equityBond));
        withdrawalManager.setWithdrawalEnabled(true);
        withdrawalManager.setRewardContractAuthorization(rewardContract, true);
        
        // 给用户分配代币
        wlgc.mint(user1, 10000 * 10**18);
        wlgc.mint(user2, 10000 * 10**18);
        wlgc.mint(turboVault, 100000 * 10**18);
        wlgc.mint(address(withdrawalManager), 100000 * 10**18); // 给合约mint代币用于directWithdraw
        usdt.mint(user1, 100000 * 10**6);
        usdt.mint(user2, 100000 * 10**6);
        
        // 授权
        vm.prank(user1);
        usdt.approve(address(withdrawalManager), type(uint256).max);
        vm.prank(user1);
        wlgc.approve(address(withdrawalManager), type(uint256).max);
        
        vm.prank(user2);
        usdt.approve(address(withdrawalManager), type(uint256).max);
        vm.prank(user2);
        wlgc.approve(address(withdrawalManager), type(uint256).max);
        
        vm.prank(turboVault);
        wlgc.approve(address(withdrawalManager), type(uint256).max);
        
        console.log("=== WithdrawalManager Test Setup Complete ===");
    }
    
    // ============ 初始化测试 ============
    
    function testInitialization() public view {
        assertEq(address(withdrawalManager.WLGC()), address(wlgc));
        assertEq(address(withdrawalManager.USDT()), address(usdt));
        assertEq(withdrawalManager.blackHole(), blackHole);
        assertEq(withdrawalManager.currentTokenPrice(), INITIAL_PRICE);
        assertEq(withdrawalManager.turboCooldown(), TURBO_COOLDOWN);
        assertTrue(withdrawalManager.withdrawalEnabled());
        
        console.log("=== Initialization Test Passed ===");
    }
    
    // ============ 余额管理测试 ============
    
    function testAddBalance() public {
        uint256 amount = 100 * 10**18;
        
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, amount, "Test reward");
        
        assertEq(withdrawalManager.getBalance(user1), amount);
        
        console.log("=== Add Balance Test Passed ===");
    }
    
    function testBatchAddBalance() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 * 10**18;
        amounts[1] = 200 * 10**18;
        
        vm.prank(rewardContract);
        withdrawalManager.batchAddBalance(users, amounts, "Daily reward");
        
        assertEq(withdrawalManager.getBalance(user1), 100 * 10**18);
        assertEq(withdrawalManager.getBalance(user2), 200 * 10**18);
        
        console.log("=== Batch Add Balance Test Passed ===");
    }
    
    function test_RevertWhen_UnauthorizedAddBalance() public {
        vm.prank(user1);
        vm.expectRevert("Withdrawal: not authorized");
        withdrawalManager.addBalance(user2, 100 * 10**18, "Test");
        
        console.log("=== Unauthorized Add Balance Test Passed ===");
    }
    
    // ============ 涡轮提现测试 ============
    
    function testRequestWithdrawal() public {
        // 先给用户添加余额
        uint256 balance = 1000 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, balance, "Test");
        
        // 请求提现
        uint256 withdrawAmount = 100 * 10**18;
        
        uint256 user1WlgcBefore = wlgc.balanceOf(user1);
        uint256 user1UsdtBefore = usdt.balanceOf(user1);
        uint256 turboVaultBefore = wlgc.balanceOf(turboVault);
        uint256 blackHoleBefore = wlgc.balanceOf(blackHole);
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 验证余额变化
        assertEq(withdrawalManager.getBalance(user1), balance - withdrawAmount);
        
        // 验证80%到涡轮
        uint256 turboAmount = (withdrawAmount * 80) / 100;
        assertEq(wlgc.balanceOf(turboVault) - turboVaultBefore, turboAmount);
        
        // 验证20%销毁
        uint256 burnAmount = withdrawAmount - turboAmount;
        assertEq(wlgc.balanceOf(blackHole) - blackHoleBefore, burnAmount);
        
        // 验证USDT支付
        uint256 requiredUSDT = withdrawalManager.getRequiredUSDT(withdrawAmount);
        assertEq(user1UsdtBefore - usdt.balanceOf(user1), requiredUSDT);
        
        // 验证WLGC转出（只转出80%到turboVault，20%从合约转出）
        assertEq(user1WlgcBefore - wlgc.balanceOf(user1), turboAmount);
        
        // 验证涡轮订单
        uint256[] memory orders = withdrawalManager.getUserTurboOrders(user1);
        assertEq(orders.length, 1);
        assertEq(orders[0], 1);
        
        WithdrawalManagerUpgradeable.TurboOrder memory order = withdrawalManager.getTurboOrder(1);
        assertEq(order.user, user1);
        assertEq(order.turboAmount, turboAmount);
        assertEq(order.withdrawAmount, withdrawAmount);
        assertFalse(order.isRedeemed);
        
        console.log("=== Request Withdrawal Test Passed ===");
        console.log("Withdraw amount:", withdrawAmount / 10**18, "WLGC");
        console.log("Turbo amount (80%):", turboAmount / 10**18, "WLGC");
        console.log("Burn amount (20%):", burnAmount / 10**18, "WLGC");
        console.log("Required USDT:", requiredUSDT / 10**6, "USDT");
    }
    
    function testRedeemTurbo() public {
        // 先请求提现
        uint256 withdrawAmount = 100 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, withdrawAmount, "Test");
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 快进12小时
        vm.warp(block.timestamp + TURBO_COOLDOWN + 1);
        
        // 赎回
        uint256 turboAmount = (withdrawAmount * 80) / 100;
        uint256 user1WlgcBefore = wlgc.balanceOf(user1);
        
        vm.prank(user1);
        withdrawalManager.redeemTurbo(1);
        
        // 验证WLGC到账
        assertEq(wlgc.balanceOf(user1) - user1WlgcBefore, turboAmount);
        
        // 验证订单状态
        WithdrawalManagerUpgradeable.TurboOrder memory order = withdrawalManager.getTurboOrder(1);
        assertTrue(order.isRedeemed);
        
        console.log("=== Redeem Turbo Test Passed ===");
    }
    
    function test_RevertWhen_RedeemBeforeCooldown() public {
        // 先请求提现
        uint256 withdrawAmount = 100 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, withdrawAmount, "Test");
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 立即尝试赎回
        vm.prank(user1);
        vm.expectRevert("Withdrawal: cooldown not finished");
        withdrawalManager.redeemTurbo(1);
        
        console.log("=== Redeem Before Cooldown Test Passed ===");
    }
    
    function test_RevertWhen_RedeemTwice() public {
        // 先请求提现
        uint256 withdrawAmount = 100 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, withdrawAmount, "Test");
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 快进12小时
        vm.warp(block.timestamp + TURBO_COOLDOWN + 1);
        
        // 第一次赎回
        vm.prank(user1);
        withdrawalManager.redeemTurbo(1);
        
        // 第二次赎回应该失败
        vm.prank(user1);
        vm.expectRevert("Withdrawal: already redeemed");
        withdrawalManager.redeemTurbo(1);
        
        console.log("=== Redeem Twice Test Passed ===");
    }
    
    function test_RevertWhen_RedeemNotOwner() public {
        // user1请求提现
        uint256 withdrawAmount = 100 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, withdrawAmount, "Test");
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 快进12小时
        vm.warp(block.timestamp + TURBO_COOLDOWN + 1);
        
        // user2尝试赎回user1的订单
        vm.prank(user2);
        vm.expectRevert("Withdrawal: not order owner");
        withdrawalManager.redeemTurbo(1);
        
        console.log("=== Redeem Not Owner Test Passed ===");
    }
    
    // ============ 直接提现测试 ============
    
    function testDirectWithdraw() public {
        // 先给用户添加余额
        uint256 balance = 1000 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, balance, "Test");
        
        // 直接提现
        uint256 withdrawAmount = 100 * 10**18;
        uint256 user1WlgcBefore = wlgc.balanceOf(user1);
        
        vm.prank(user1);
        withdrawalManager.directWithdraw(withdrawAmount);
        
        // 验证余额
        assertEq(withdrawalManager.getBalance(user1), balance - withdrawAmount);
        assertEq(wlgc.balanceOf(user1) - user1WlgcBefore, withdrawAmount);
        
        console.log("=== Direct Withdraw Test Passed ===");
    }
    
    function test_RevertWhen_DirectWithdrawInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert("Withdrawal: insufficient balance");
        withdrawalManager.directWithdraw(100 * 10**18);
        
        console.log("=== Direct Withdraw Insufficient Balance Test Passed ===");
    }
    
    // ============ 配置管理测试 ============
    
    function testSetTokenPrice() public {
        uint256 newPrice = 2 * 10**6;
        withdrawalManager.updateTokenPrice(newPrice);
        assertEq(withdrawalManager.currentTokenPrice(), newPrice);
        
        console.log("=== Set Token Price Test Passed ===");
    }
    
    function testSetTurboCooldown() public {
        uint256 newCooldown = 24 hours;
        withdrawalManager.setTurboCooldown(newCooldown);
        assertEq(withdrawalManager.turboCooldown(), newCooldown);
        
        console.log("=== Set Turbo Cooldown Test Passed ===");
    }
    
    function testSetWithdrawalEnabled() public {
        withdrawalManager.setWithdrawalEnabled(false);
        assertFalse(withdrawalManager.withdrawalEnabled());
        
        withdrawalManager.setWithdrawalEnabled(true);
        assertTrue(withdrawalManager.withdrawalEnabled());
        
        console.log("=== Set Withdrawal Enabled Test Passed ===");
    }
    
    function test_RevertWhen_WithdrawWhenDisabled() public {
        withdrawalManager.setWithdrawalEnabled(false);
        
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, 100 * 10**18, "Test");
        
        vm.prank(user1);
        vm.expectRevert("Withdrawal: not enabled");
        withdrawalManager.requestWithdrawal(100 * 10**18);
        
        console.log("=== Withdraw When Disabled Test Passed ===");
    }
    
    // ============ 查询功能测试 ============
    
    function testGetRequiredUSDT() public view {
        uint256 wlgcAmount = 100 * 10**18;
        uint256 requiredUSDT = withdrawalManager.getRequiredUSDT(wlgcAmount);
        
        // 需要购买80% = 80 WLGC
        // 价格1 USDT，所以需要80 USDT
        assertEq(requiredUSDT, 80 * 10**6);
        
        console.log("=== Get Required USDT Test Passed ===");
        console.log("WLGC amount:", wlgcAmount / 10**18);
        console.log("Required USDT:", requiredUSDT / 10**6);
    }
    
    function testCanRedeemTurbo() public {
        // 先请求提现
        uint256 withdrawAmount = 100 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, withdrawAmount, "Test");
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 检查是否可以赎回（未到时间）
        (bool canRedeem, string memory reason) = withdrawalManager.canRedeemTurbo(1);
        assertFalse(canRedeem);
        
        // 快进12小时
        vm.warp(block.timestamp + TURBO_COOLDOWN + 1);
        
        // 再次检查
        (canRedeem, reason) = withdrawalManager.canRedeemTurbo(1);
        assertTrue(canRedeem);
        assertEq(reason, "Can redeem");
        
        console.log("=== Can Redeem Turbo Test Passed ===");
    }
    
    function testDiagnoseWithdrawal() public {
        // 给用户添加余额
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, 100 * 10**18, "Test");
        
        // 诊断
        (bool canWithdraw, string memory reason) = withdrawalManager.diagnoseWithdrawal(user1, 100 * 10**18);
        assertTrue(canWithdraw);
        assertEq(reason, "Can withdraw");
        
        console.log("=== Diagnose Withdrawal Test Passed ===");
    }
    
    function testGetGlobalStats() public {
        // 先做一次提现
        uint256 withdrawAmount = 100 * 10**18;
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, withdrawAmount, "Test");
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(withdrawAmount);
        
        // 获取统计
        (
            uint256 totalWithdrawn,
            uint256 totalEquityGenerated,
            uint256 totalBurned,
            uint256 totalTurboLocked
        ) = withdrawalManager.getGlobalStats();
        
        assertEq(totalWithdrawn, withdrawAmount);
        assertEq(totalEquityGenerated, withdrawAmount * 20 / 100);
        assertEq(totalBurned, withdrawAmount * 20 / 100);
        assertEq(totalTurboLocked, withdrawAmount * 80 / 100);
        
        console.log("=== Get Global Stats Test Passed ===");
        console.log("Total withdrawn:", totalWithdrawn / 10**18, "WLGC");
        console.log("Total equity generated:", totalEquityGenerated / 10**18, "WLGC");
        console.log("Total burned:", totalBurned / 10**18, "WLGC");
        console.log("Total turbo locked:", totalTurboLocked / 10**18, "WLGC");
    }
    
    // ============ 多用户测试 ============
    
    function testMultipleUsersWithdrawal() public {
        // 给两个用户添加余额
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, 100 * 10**18, "Test");
        
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user2, 200 * 10**18, "Test");
        
        // user1提现
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(50 * 10**18);
        
        // user2提现
        vm.prank(user2);
        withdrawalManager.requestWithdrawal(100 * 10**18);
        
        // 验证订单
        assertEq(withdrawalManager.getUserTurboOrderCount(user1), 1);
        assertEq(withdrawalManager.getUserTurboOrderCount(user2), 1);
        
        // 验证余额
        assertEq(withdrawalManager.getBalance(user1), 50 * 10**18);
        assertEq(withdrawalManager.getBalance(user2), 100 * 10**18);
        
        console.log("=== Multiple Users Withdrawal Test Passed ===");
    }
    
    function testMultipleTurboOrders() public {
        // 给用户添加余额
        vm.prank(rewardContract);
        withdrawalManager.addBalance(user1, 1000 * 10**18, "Test");
        
        // 多次提现
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(100 * 10**18);
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(200 * 10**18);
        
        vm.prank(user1);
        withdrawalManager.requestWithdrawal(300 * 10**18);
        
        // 验证订单数量
        assertEq(withdrawalManager.getUserTurboOrderCount(user1), 3);
        
        // 验证余额
        assertEq(withdrawalManager.getBalance(user1), 400 * 10**18);
        
        // 快进12小时
        vm.warp(block.timestamp + TURBO_COOLDOWN + 1);
        
        // 赎回所有订单
        vm.prank(user1);
        withdrawalManager.redeemTurbo(1);
        
        vm.prank(user1);
        withdrawalManager.redeemTurbo(2);
        
        vm.prank(user1);
        withdrawalManager.redeemTurbo(3);
        
        // 验证所有订单已赎回
        assertTrue(withdrawalManager.getTurboOrder(1).isRedeemed);
        assertTrue(withdrawalManager.getTurboOrder(2).isRedeemed);
        assertTrue(withdrawalManager.getTurboOrder(3).isRedeemed);
        
        console.log("=== Multiple Turbo Orders Test Passed ===");
    }
    
    // ============ 价格变化测试 ============
    
    function testRequiredUSDTWithPriceChange() public {
        uint256 wlgcAmount = 100 * 10**18;
        
        // 价格1 USDT
        uint256 required1 = withdrawalManager.getRequiredUSDT(wlgcAmount);
        assertEq(required1, 80 * 10**6);
        
        // 价格变为2 USDT
        withdrawalManager.updateTokenPrice(2 * 10**6);
        uint256 required2 = withdrawalManager.getRequiredUSDT(wlgcAmount);
        assertEq(required2, 160 * 10**6);
        
        // 价格变为0.5 USDT
        withdrawalManager.updateTokenPrice(0.5 * 10**6);
        uint256 required3 = withdrawalManager.getRequiredUSDT(wlgcAmount);
        assertEq(required3, 40 * 10**6);
        
        console.log("=== Required USDT With Price Change Test Passed ===");
        console.log("Price 1 USDT, required:", required1 / 10**6, "USDT");
        console.log("Price 2 USDT, required:", required2 / 10**6, "USDT");
        console.log("Price 0.5 USDT, required:", required3 / 10**6, "USDT");
    }
    
    // ============ 权限测试 ============
    
    function test_RevertWhen_OnlyOwnerCanSetConfig() public {
        vm.prank(user1);
        vm.expectRevert();
        withdrawalManager.updateTokenPrice(2 * 10**6);
        
        console.log("=== Only Owner Can Set Config Test Passed ===");
    }
}
