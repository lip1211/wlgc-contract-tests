// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/WlgcToken.sol";
import "../contracts/MockERC20.sol";

// Mock Uniswap V2 Pair
contract MockUniswapV2Pair {
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
    
    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
    }
    
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }
}

contract WlgcTokenTest is Test {
    WlgcToken public wlgc;
    MockERC20 public usdt;
    MockUniswapV2Pair public pair;
    
    address public owner;
    address public user1;
    address public user2;
    address public genesisReceiver;
    address public superReceiver;
    address public opsReceiver;
    address public consensusPool;
    address public router;
    
    uint256 constant INITIAL_SUPPLY = 100_000_000 * 10**18; // 1亿
    uint256 constant INITIAL_PRICE = 1 * 10**18; // 1 USDT per WLGC
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        genesisReceiver = address(0x10);
        superReceiver = address(0x11);
        opsReceiver = address(0x12);
        consensusPool = address(0x13);
        router = address(0x14);
        
        // 部署USDT
        usdt = new MockERC20("USDT", "USDT", 18);
        
        // 部署WLGC
        wlgc = new WlgcToken("WLGC Token", "WLGC", INITIAL_SUPPLY, owner);
        
        // 创建交易对
        pair = new MockUniswapV2Pair(address(wlgc), address(usdt));
        
        // 设置初始储备量（1:1价格）
        // 假设池子里有100万WLGC和100万USDT
        pair.setReserves(1_000_000 * 10**18, 1_000_000 * 10**18);
        
        // 配置WLGC
        wlgc.setMainPair(address(pair), address(usdt));
        wlgc.setRouter(router, true); // router加入白名单
        wlgc.setFeeReceivers(genesisReceiver, superReceiver, opsReceiver, consensusPool);
        wlgc.setInitialRefPriceE18(INITIAL_PRICE);
        wlgc.setRefUpdateIntervalBlocks(100); // 每100个区块更新一次
        wlgc.setCooldownBlocks(3); // 3个区块冷却
        
        // 给用户分配代币
        wlgc.transfer(user1, 1_000_000 * 10**18);
        wlgc.transfer(user2, 1_000_000 * 10**18);
        wlgc.transfer(address(pair), 1_000_000 * 10**18); // 给pair代币
        
        // 给pair分配USDT
        usdt.mint(address(pair), 1_000_000 * 10**18);
    }
    
    // ============ 初始化测试 ============
    
    function testInitialization() public {
        assertEq(wlgc.name(), "WLGC Token");
        assertEq(wlgc.symbol(), "WLGC");
        assertEq(wlgc.decimals(), 18);
        assertEq(wlgc.totalSupply(), INITIAL_SUPPLY);
        assertEq(wlgc.owner(), owner);
        assertTrue(wlgc.isWhitelisted(owner)); // owner默认在白名单
    }
    
    function testConstants() public {
        assertEq(wlgc.BPS_DENOMINATOR(), 10_000);
        assertEq(wlgc.BASE_INTO_PAIR_BPS(), 600); // 6%
        assertEq(wlgc.BASE_BURN_BPS(), 100); // 1%
        assertEq(wlgc.BASE_GENESIS_BPS(), 100); // 1%
        assertEq(wlgc.BASE_SUPER_BPS(), 100); // 1%
        assertEq(wlgc.BASE_OPS_BPS(), 300); // 3%
        assertEq(wlgc.EXTRA_MAX_STEPS(), 12);
        assertEq(wlgc.EXTRA_STEP_BPS(), 200); // 2%
        assertEq(wlgc.EXTRA_TRIGGER_DROP_BPS(), 1500); // 15%
        assertEq(wlgc.SLIPPAGE_OFF_CIRCULATING(), 10_000_000 * 10**18);
    }
    
    // ============ 基础转账测试 ============
    
    function testBasicTransfer() public {
        uint256 amount = 1000 * 10**18;
        uint256 user1Before = wlgc.balanceOf(user1);
        uint256 user2Before = wlgc.balanceOf(user2);
        
        vm.prank(user1);
        wlgc.transfer(user2, amount);
        
        assertEq(wlgc.balanceOf(user1), user1Before - amount);
        assertEq(wlgc.balanceOf(user2), user2Before + amount);
    }
    
    function testApproveAndTransferFrom() public {
        uint256 amount = 1000 * 10**18;
        
        vm.prank(user1);
        wlgc.approve(user2, amount);
        
        assertEq(wlgc.allowance(user1, user2), amount);
        
        vm.prank(user2);
        wlgc.transferFrom(user1, user2, amount);
        
        assertEq(wlgc.allowance(user1, user2), 0);
    }
    
    // ============ 白名单测试 ============
    
    function testSetWhitelist() public {
        assertFalse(wlgc.isWhitelisted(user1));
        
        wlgc.setWhitelist(user1, true);
        assertTrue(wlgc.isWhitelisted(user1));
        
        wlgc.setWhitelist(user1, false);
        assertFalse(wlgc.isWhitelisted(user1));
    }
    
    function testSetWhitelistBatch() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = address(0x3);
        
        wlgc.setWhitelistBatch(accounts, true);
        
        assertTrue(wlgc.isWhitelisted(user1));
        assertTrue(wlgc.isWhitelisted(user2));
        assertTrue(wlgc.isWhitelisted(address(0x3)));
    }
    
    function testWhitelistBypassesFees() public {
        // 将user1加入白名单
        wlgc.setWhitelist(user1, true);
        
        uint256 amount = 1000 * 10**18;
        uint256 user1Before = wlgc.balanceOf(user1);
        uint256 pairBefore = wlgc.balanceOf(address(pair));
        
        // 白名单用户卖出到pair，不收费
        vm.prank(user1);
        wlgc.transfer(address(pair), amount);
        
        // 验证全额到账，无费用
        assertEq(wlgc.balanceOf(user1), user1Before - amount);
        assertEq(wlgc.balanceOf(address(pair)), pairBefore + amount);
    }
    
    // ============ 买盘开关测试 ============
    
    function testBuyDisabledByDefault() public {
        assertFalse(wlgc.buyEnabled());
    }
    
    function testSetBuyEnabled() public {
        wlgc.setBuyEnabled(true);
        assertTrue(wlgc.buyEnabled());
        
        wlgc.setBuyEnabled(false);
        assertFalse(wlgc.buyEnabled());
    }
    
    function test_RevertWhen_BuyDisabled() public {
        // 买盘关闭时，从pair转出（买入）应该失败
        uint256 amount = 1000 * 10**18;
        
        vm.prank(address(pair));
        vm.expectRevert("buy disabled");
        wlgc.transfer(user1, amount);
    }
    
    function testBuyEnabledAllowsPurchase() public {
        wlgc.setBuyEnabled(true);
        
        uint256 amount = 1000 * 10**18;
        uint256 user1Before = wlgc.balanceOf(user1);
        
        vm.prank(address(pair));
        wlgc.transfer(user1, amount);
        
        assertEq(wlgc.balanceOf(user1), user1Before + amount);
    }
    
    function testWhitelistBypassesBuySwitch() public {
        // 白名单用户即使买盘关闭也能买
        wlgc.setWhitelist(user1, true);
        
        uint256 amount = 1000 * 10**18;
        
        vm.prank(address(pair));
        wlgc.transfer(user1, amount); // 不应该revert
    }
    
    // ============ 冷却机制测试 ============
    
    function testCooldownBlocks() public {
        assertEq(wlgc.cooldownBlocks(), 3);
        
        wlgc.setCooldownBlocks(5);
        assertEq(wlgc.cooldownBlocks(), 5);
    }
    
    function test_RevertWhen_WithinCooldown() public {
        uint256 amount = 1000 * 10**18;
        
        // 第一次转账
        vm.prank(user1);
        wlgc.transfer(user2, amount);
        
        // 立即再次转账应该失败（冷却期内）
        vm.prank(user1);
        vm.expectRevert("cooldown");
        wlgc.transfer(user2, amount);
    }
    
    function testCooldownPassesAfterBlocks() public {
        uint256 amount = 1000 * 10**18;
        
        // 第一次转账
        vm.prank(user1);
        wlgc.transfer(user2, amount);
        
        // 前进4个区块（超过3个区块冷却）
        vm.roll(block.number + 4);
        
        // 现在应该可以转账
        vm.prank(user1);
        wlgc.transfer(user2, amount); // 不应该revert
    }
    
    function testWhitelistBypassesCooldown() public {
        wlgc.setWhitelist(user1, true);
        
        uint256 amount = 1000 * 10**18;
        
        // 连续转账不应该失败
        vm.startPrank(user1);
        wlgc.transfer(user2, amount);
        wlgc.transfer(user2, amount); // 不应该revert
        vm.stopPrank();
    }
    
    // ============ 转账限制测试 ============
    
    function testTransferLimit99_9999Percent() public {
        uint256 balance = wlgc.balanceOf(user1);
        uint256 maxTransfer = (balance * 999_999) / 1_000_000; // 99.9999%
        
        vm.roll(block.number + 4); // 避免冷却
        
        // 转账99.9999%应该成功
        vm.prank(user1);
        wlgc.transfer(user2, maxTransfer);
    }
    
    function test_RevertWhen_ExceedsTransferLimit() public {
        uint256 balance = wlgc.balanceOf(user1);
        
        vm.roll(block.number + 4);
        
        // 转账100%应该失败
        vm.prank(user1);
        vm.expectRevert();
        wlgc.transfer(user2, balance);
    }
    
    function testWhitelistBypassesTransferLimit() public {
        wlgc.setWhitelist(user1, true);
        
        uint256 balance = wlgc.balanceOf(user1);
        
        // 白名单用户可以转账100%
        vm.prank(user1);
        wlgc.transfer(user2, balance); // 不应该revert
    }
    
    // ============ 单笔限制测试（池子的1%）============
    
    function testMaxTxLimit1Percent() public {
        wlgc.setBuyEnabled(true);
        
        // 池子储备量是1,000,000，1%是10,000
        uint256 maxTx = 10_000 * 10**18;
        
        vm.roll(block.number + 4);
        
        // 从pair买入10,000应该成功
        vm.prank(address(pair));
        wlgc.transfer(user1, maxTx);
    }
    
    function test_RevertWhen_ExceedsMaxTx() public {
        wlgc.setBuyEnabled(true);
        
        // 超过1%应该失败
        uint256 overMaxTx = 10_001 * 10**18;
        
        vm.prank(address(pair));
        vm.expectRevert("maxTx");
        wlgc.transfer(user1, overMaxTx);
    }
    
    // ============ 基础费用测试（6%）============
    
    function testBaseFees6Percent() public {
        uint256 amount = 10_000 * 10**18;
        
        // 清空接收地址余额
        uint256 genesisBefore = wlgc.balanceOf(genesisReceiver);
        uint256 superBefore = wlgc.balanceOf(superReceiver);
        uint256 opsBefore = wlgc.balanceOf(opsReceiver);
        uint256 deadBefore = wlgc.balanceOf(wlgc.DEAD());
        
        vm.roll(block.number + 4);
        
        // user1卖出到pair，触发6%费用
        vm.prank(user1);
        wlgc.transfer(address(pair), amount);
        
        // 验证费用分配
        // 1% 销毁
        assertEq(wlgc.balanceOf(wlgc.DEAD()) - deadBefore, (amount * 100) / 10_000);
        // 1% 创世节点
        assertEq(wlgc.balanceOf(genesisReceiver) - genesisBefore, (amount * 100) / 10_000);
        // 1% 超级节点
        assertEq(wlgc.balanceOf(superReceiver) - superBefore, (amount * 100) / 10_000);
        // 3% 运营
        assertEq(wlgc.balanceOf(opsReceiver) - opsBefore, (amount * 300) / 10_000);
        
        // pair实际收到94%
        uint256 expectedReceived = (amount * 9400) / 10_000;
        // 注意：这里需要考虑动态费用，如果价格没变化，动态费用为0
    }
    
    // ============ 动态额外费用测试 ============
    
    function testExtraFeeWhenPriceDrop15Percent() public {
        // 设置参考价为1 USDT
        wlgc.setInitialRefPriceE18(1 * 10**18);
        
        // 模拟价格下跌到0.84 USDT（下跌16%）
        // 储备量调整：WLGC增加，USDT减少
        pair.setReserves(1_190_476 * 10**18, 1_000_000 * 10**18);
        // 新价格 = 1_000_000 / 1_190_476 ≈ 0.84
        
        uint256 amount = 10_000 * 10**18;
        
        uint256 consensusBefore = wlgc.balanceOf(consensusPool);
        uint256 deadBefore = wlgc.balanceOf(wlgc.DEAD());
        
        vm.roll(block.number + 4);
        
        // 卖出触发动态费用
        vm.prank(user1);
        wlgc.transfer(address(pair), amount);
        
        // 下跌16%，超过15%触发点，应该有额外2%费用
        // 额外费用的一半销毁，一半给共识池
        uint256 extraFee = (amount * 200) / 10_000; // 2%
        uint256 extraBurn = extraFee / 2 + (extraFee % 2);
        uint256 extraConsensus = extraFee / 2;
        
        // 验证额外费用（注意：还有基础费用的销毁）
        assertTrue(wlgc.balanceOf(consensusPool) - consensusBefore >= extraConsensus);
    }
    
    // ============ 通缩关闭测试 ============
    
    function testSlippageOffWhenCirculatingBelow10M() public {
        // 初始流通量是100M，应该不关闭
        assertFalse(wlgc.isSlippageOff());
    }
    
    function testSlippageOffWhenCirculatingAbove10M() public {
        // 销毁大量代币，使流通量低于1000万
        uint256 toBurn = 91_000_000 * 10**18;
        wlgc.transfer(wlgc.DEAD(), toBurn);
        
        // 现在流通量约9M，应该关闭滑点
        assertTrue(wlgc.isSlippageOff());
    }
    
    function testNoFeesWhenSlippageOff() public {
        // 销毁代币使流通量低于1000万
        uint256 toBurn = 91_000_000 * 10**18;
        wlgc.transfer(wlgc.DEAD(), toBurn);
        
        assertTrue(wlgc.isSlippageOff());
        
        // 给user1更多代币
        wlgc.transfer(user1, 1_000_000 * 10**18);
        
        uint256 amount = 10_000 * 10**18;
        uint256 pairBefore = wlgc.balanceOf(address(pair));
        
        vm.roll(block.number + 4);
        
        // 卖出到pair，不应该收费
        vm.prank(user1);
        wlgc.transfer(address(pair), amount);
        
        // 验证全额到账
        assertEq(wlgc.balanceOf(address(pair)), pairBefore + amount);
    }
    
    // ============ 参考价更新测试 ============
    
    function testRefPriceUpdate() public {
        uint256 initialRefPrice = wlgc.refPriceE18();
        
        // 前进100个区块（达到更新间隔）
        vm.roll(block.number + 100);
        
        // 任何转账都会触发价格更新
        vm.prank(user1);
        wlgc.transfer(user2, 1000 * 10**18);
        
        // 参考价应该更新
        uint256 newRefPrice = wlgc.refPriceE18();
        // 由于池子储备量没变，价格应该相同
        assertEq(newRefPrice, initialRefPrice);
    }
    
    // ============ 查询功能测试 ============
    
    function testCirculatingSupply() public {
        uint256 totalSupply = wlgc.totalSupply();
        uint256 deadBalance = wlgc.balanceOf(wlgc.DEAD());
        uint256 circulating = wlgc.circulatingSupply();
        
        assertEq(circulating, totalSupply - deadBalance);
    }
    
    function testGetCurrentPrice() public {
        uint256 price = wlgc.getCurrentPriceE18();
        // 池子是1:1，价格应该接近1 USDT
        assertApproxEqRel(price, 1 * 10**18, 0.01e18); // 1%误差
    }
    
    function testGetReserves() public {
        (uint256 reserveToken, uint256 reserveUsdt) = wlgc.getReservesTokenUsdt();
        assertEq(reserveToken, 1_000_000 * 10**18);
        assertEq(reserveUsdt, 1_000_000 * 10**18);
    }
    
    // ============ 权限控制测试 ============
    
    function test_RevertWhen_NonOwnerSetsWhitelist() public {
        vm.prank(user1);
        vm.expectRevert();
        wlgc.setWhitelist(user2, true);
    }
    
    function test_RevertWhen_NonOwnerSetsBuyEnabled() public {
        vm.prank(user1);
        vm.expectRevert();
        wlgc.setBuyEnabled(true);
    }
    
    function test_RevertWhen_NonOwnerSetsFeeReceivers() public {
        vm.prank(user1);
        vm.expectRevert();
        wlgc.setFeeReceivers(genesisReceiver, superReceiver, opsReceiver, consensusPool);
    }
    
    function test_RevertWhen_NonOwnerSetsRefPrice() public {
        vm.prank(user1);
        vm.expectRevert();
        wlgc.setInitialRefPriceE18(2 * 10**18);
    }
    
    // ============ 配置管理测试 ============
    
    function testSetFeeReceivers() public {
        address newGenesis = address(0x20);
        address newSuper = address(0x21);
        address newOps = address(0x22);
        address newConsensus = address(0x23);
        
        wlgc.setFeeReceivers(newGenesis, newSuper, newOps, newConsensus);
        
        assertEq(wlgc.genesisNodeReceiver(), newGenesis);
        assertEq(wlgc.superNodeReceiver(), newSuper);
        assertEq(wlgc.opsReceiver(), newOps);
        assertEq(wlgc.consensusPool(), newConsensus);
    }
    
    function testSetRouter() public {
        address newRouter = address(0x30);
        
        wlgc.setRouter(newRouter, true);
        
        assertEq(wlgc.router(), newRouter);
        assertTrue(wlgc.isWhitelisted(newRouter)); // 应该自动加入白名单
    }
    
    function testSetMainPair() public {
        MockERC20 newUsdt = new MockERC20("New USDT", "USDT2", 6); // 6位精度
        MockUniswapV2Pair newPair = new MockUniswapV2Pair(address(wlgc), address(newUsdt));
        
        wlgc.setMainPair(address(newPair), address(newUsdt));
        
        assertEq(wlgc.mainPair(), address(newPair));
        assertEq(wlgc.usdt(), address(newUsdt));
        assertEq(wlgc.usdtDecimals(), 6);
        assertEq(wlgc.refPriceE18(), 0); // 应该重置
    }
}
