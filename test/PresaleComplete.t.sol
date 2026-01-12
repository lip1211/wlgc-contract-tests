// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ReferralRegistry.sol";
import "../contracts/NodeRegistry.sol";
import "../contracts/PresaleUpgradeable.sol";
import "../contracts/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PresaleCompleteTest - 完整的预售合约测试套件
 * @notice 测试预售合约的所有功能，包括双代币支付
 */
contract PresaleCompleteTest is Test {
    ReferralRegistry public referralRegistry;
    NodeRegistry public nodeRegistry;
    PresaleUpgradeable public presale;
    MockERC20 public usdt;
    MockERC20 public usd1;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public paymentAddr;
    
    uint256 constant BASE_TOKEN_PRICE = 1 * 10**18; // 1 USDT (18精度)

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        paymentAddr = makeAddr("payment");

        // 部署USDT（18精度，用于测试）
        usdt = new MockERC20("Test USDT", "TUSDT", 18);
        
        // 部署USD1（18精度，用于测试）
        usd1 = new MockERC20("Test USD1", "TUSD1", 18);

        // 部署ReferralRegistry
        referralRegistry = new ReferralRegistry();
        
        // 部署NodeRegistry
        nodeRegistry = new NodeRegistry();

        // 部署Presale（代理模式）
        PresaleUpgradeable implementation = new PresaleUpgradeable();
        bytes memory initData = abi.encodeWithSelector(
            PresaleUpgradeable.initialize.selector,
            address(usdt),
            address(usd1),  // ⭐ 添加USD1地址
            address(referralRegistry),
            address(nodeRegistry),
            BASE_TOKEN_PRICE
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        presale = PresaleUpgradeable(address(proxy));

        // 铸造USDT给用户（每人10万）
        usdt.mint(user1, 100000 * 10**18);
        usdt.mint(user2, 100000 * 10**18);
        usdt.mint(user3, 100000 * 10**18);
        usdt.mint(user4, 100000 * 10**18);
        
        // 铸造USD1给用户（每人10万）
        usd1.mint(user1, 100000 * 10**18);
        usd1.mint(user2, 100000 * 10**18);
        usd1.mint(user3, 100000 * 10**18);
        usd1.mint(user4, 100000 * 10**18);

        // 设置根节点
        address platformRoot = address(0x1);
        referralRegistry.setRootAddress(platformRoot);
        referralRegistry.adminSetInvite(user1, platformRoot);
        
        // ⭐ 授权Presale合约可以操作推荐关系
        referralRegistry.setAuthorizedCaller(address(presale), true);
        
        // ⭐ 授权Presale合约可以更新节点信息
        nodeRegistry.setAuthorizedCaller(address(presale), true);

        // 添加收款地址
        presale.addPaymentAddress(paymentAddr);

        // 激活预售
        presale.setPresaleActive(true);
    }

    // ============ 基础功能测试 ============

    function testInitialization() public view {
        assertEq(address(presale.USDT()), address(usdt));
        assertEq(address(presale.USD1()), address(usd1));
        assertEq(address(presale.referralRegistry()), address(referralRegistry));
        assertEq(address(presale.nodeRegistry()), address(nodeRegistry));
        assertEq(presale.baseTokenPrice(), BASE_TOKEN_PRICE);
        assertTrue(presale.presaleActive());
        
        console.log("=== Initialization Test Passed ===");
        console.log("USDT:", address(usdt));
        console.log("USD1:", address(usd1));
        console.log("Base Token Price:", BASE_TOKEN_PRICE);
    }

    function testNodeConfig() public view {
        INodeRegistry.NodeConfig memory community = presale.getNodeConfig(INodeRegistry.NodeType.COMMUNITY);
        // 实际配置从NodeRegistry读取，不做硬编码断言
        assertTrue(community.price > 0);
        assertTrue(community.maxQuota > 0);
        
        INodeRegistry.NodeConfig memory super_ = presale.getNodeConfig(INodeRegistry.NodeType.SUPER);
        assertTrue(super_.price > 0);
        assertTrue(super_.maxQuota > 0);
        
        INodeRegistry.NodeConfig memory genesis = presale.getNodeConfig(INodeRegistry.NodeType.GENESIS);
        assertTrue(genesis.price > 0);
        assertTrue(genesis.maxQuota > 0);
        
        // 验证价格递增关系
        assertTrue(super_.price > community.price);
        assertTrue(genesis.price > super_.price);
        
        console.log("=== Node Config Test Passed ===");
        console.log("Community Node Price:", community.price / 10**18, "USDT");
        console.log("Super Node Price:", super_.price / 10**18, "USDT");
        console.log("Genesis Node Price:", genesis.price / 10**18, "USDT");
    }

    // ============ 推荐关系测试 ============

    function testBindReferrerDirectly() public {
        vm.prank(user2);
        referralRegistry.setInvite(user1);
        
        assertEq(referralRegistry.getUpline(user2), user1);
        assertTrue(referralRegistry.hasUpline(user2));
        
        console.log("=== Direct Bind Referrer Test Passed ===");
        console.log("User2 referrer:", referralRegistry.getUpline(user2));
    }
    
    function testBindReferrerViaPresale() public {
        vm.prank(user2);
        presale.bindReferrer(user1);
        
        assertEq(referralRegistry.getUpline(user2), user1);
        assertTrue(referralRegistry.hasUpline(user2));
        assertEq(presale.getReferrer(user2), user1);
        assertTrue(presale.hasValidReferrer(user2));
        
        console.log("=== Bind Referrer Via Presale Test Passed ===");
        console.log("User2 referrer:", presale.getReferrer(user2));
    }

    function testCannotBindSelfAsReferrer() public {
        vm.prank(user2);
        vm.expectRevert();
        presale.bindReferrer(user2);
        
        console.log("=== Cannot Bind Self Test Passed ===");
    }

    function testCannotBindZeroAddress() public {
        vm.prank(user2);
        vm.expectRevert();
        presale.bindReferrer(address(0));
        
        console.log("=== Cannot Bind Zero Address Test Passed ===");
    }

    // ============ 节点购买测试（USDT） ============

    function testPurchaseCommunityNodeWithUSDT() public {
        // user2绑定推荐人
        vm.prank(user2);
        presale.bindReferrer(user1);

        // 授权USDT
        vm.prank(user2);
        usdt.approve(address(presale), 1000 * 10**18);

        // 记录购买前余额
        uint256 balanceBefore = usdt.balanceOf(paymentAddr);

        // 认购社区节点
        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USDT);

        // 验证节点信息
        INodeRegistry.UserInfo memory info = presale.getUserInfo(user2);
        assertEq(uint(info.nodeType), uint(INodeRegistry.NodeType.COMMUNITY));
        assertEq(uint(info.level), uint(INodeRegistry.UserLevel.W1));
        assertEq(info.personalPurchase, 1000 * 10**18);

        // 验证收款
        assertEq(usdt.balanceOf(paymentAddr) - balanceBefore, 1000 * 10**18);

        // 验证社区业绩
        INodeRegistry.UserInfo memory user1Info = presale.getUserInfo(user1);
        assertEq(user1Info.communityPurchase, 1000 * 10**18);
        
        console.log("=== Purchase Community Node with USDT Test Passed ===");
        console.log("User2 node type:", uint(info.nodeType));
        console.log("User2 personal purchase:", info.personalPurchase / 10**18, "USDT");
        console.log("User1 community purchase:", user1Info.communityPurchase / 10**18, "USDT");
    }

    function testPurchaseSuperNodeWithUSDT() public {
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usdt.approve(address(presale), 5000 * 10**18);

        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.SUPER, PresaleUpgradeable.PaymentToken.USDT);

        INodeRegistry.UserInfo memory info = presale.getUserInfo(user2);
        assertEq(uint(info.nodeType), uint(INodeRegistry.NodeType.SUPER));
        assertEq(info.personalPurchase, 5000 * 10**18);
        
        console.log("=== Purchase Super Node with USDT Test Passed ===");
    }

    function testPurchaseGenesisNodeWithUSDT() public {
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usdt.approve(address(presale), 20000 * 10**18);

        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.GENESIS, PresaleUpgradeable.PaymentToken.USDT);

        INodeRegistry.UserInfo memory info = presale.getUserInfo(user2);
        assertEq(uint(info.nodeType), uint(INodeRegistry.NodeType.GENESIS));
        assertEq(info.personalPurchase, 20000 * 10**18);
        
        console.log("=== Purchase Genesis Node with USDT Test Passed ===");
    }

    // ============ 节点购买测试（USD1） ============

    function testPurchaseCommunityNodeWithUSD1() public {
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usd1.approve(address(presale), 1000 * 10**18);

        uint256 balanceBefore = usd1.balanceOf(paymentAddr);

        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USD1);

        INodeRegistry.UserInfo memory info = presale.getUserInfo(user2);
        assertEq(uint(info.nodeType), uint(INodeRegistry.NodeType.COMMUNITY));
        assertEq(usd1.balanceOf(paymentAddr) - balanceBefore, 1000 * 10**18);
        
        console.log("=== Purchase Community Node with USD1 Test Passed ===");
    }

    // ============ 推荐链测试 ============

    function testReferralChain() public {
        // user1 <- user2 <- user3 <- user4
        vm.prank(user2);
        presale.bindReferrer(user1);
        
        vm.prank(user3);
        presale.bindReferrer(user2);
        
        vm.prank(user4);
        presale.bindReferrer(user3);

        // user4购买节点
        vm.prank(user4);
        usdt.approve(address(presale), 1000 * 10**18);
        
        vm.prank(user4);
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USDT);

        // 验证推荐链的社区业绩
        INodeRegistry.UserInfo memory user3Info = presale.getUserInfo(user3);
        INodeRegistry.UserInfo memory user2Info = presale.getUserInfo(user2);
        INodeRegistry.UserInfo memory user1Info = presale.getUserInfo(user1);
        
        assertEq(user3Info.communityPurchase, 1000 * 10**18);
        assertEq(user2Info.communityPurchase, 1000 * 10**18);
        assertEq(user1Info.communityPurchase, 1000 * 10**18);
        
        console.log("=== Referral Chain Test Passed ===");
        console.log("User3 community purchase:", user3Info.communityPurchase / 10**18);
        console.log("User2 community purchase:", user2Info.communityPurchase / 10**18);
        console.log("User1 community purchase:", user1Info.communityPurchase / 10**18);
    }

    // ============ 错误情况测试 ============

    function testCannotPurchaseWithoutReferrer() public {
        vm.prank(user3);
        usdt.approve(address(presale), 1000 * 10**18);

        vm.prank(user3);
        vm.expectRevert("Presale: no referrer bound");
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USDT);
        
        console.log("=== Cannot Purchase Without Referrer Test Passed ===");
    }

    function testCannotPurchaseTwice() public {
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usdt.approve(address(presale), 100000 * 10**18);

        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USDT);

        vm.prank(user2);
        vm.expectRevert("Presale: already purchased");
        presale.purchaseNode(INodeRegistry.NodeType.SUPER, PresaleUpgradeable.PaymentToken.USDT);
        
        console.log("=== Cannot Purchase Twice Test Passed ===");
    }

    function testCannotPurchaseWhenInactive() public {
        presale.setPresaleActive(false);
        
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usdt.approve(address(presale), 1000 * 10**18);

        vm.prank(user2);
        vm.expectRevert("Presale: presale not active");
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USDT);
        
        console.log("=== Cannot Purchase When Inactive Test Passed ===");
    }

    function testQuotaLimit() public {
        // 设置创世节点份额为1
        nodeRegistry.updateNodeConfig(
            NodeRegistry.NodeType.GENESIS,
            20000 * 10**18,
            1,
            8000,
            6
        );

        // user2认购
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usdt.approve(address(presale), 20000 * 10**18);

        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.GENESIS, PresaleUpgradeable.PaymentToken.USDT);

        // user3尝试认购（应该失败）
        vm.prank(user3);
        presale.bindReferrer(user1);

        vm.prank(user3);
        usdt.approve(address(presale), 20000 * 10**18);

        vm.prank(user3);
        vm.expectRevert("Presale: quota exceeded");
        presale.purchaseNode(INodeRegistry.NodeType.GENESIS, PresaleUpgradeable.PaymentToken.USDT);
        
        console.log("=== Quota Limit Test Passed ===");
    }

    // ============ 查询功能测试 ============

    function testGetRemainingQuota() public view {
        uint256 remaining = presale.getRemainingQuota(INodeRegistry.NodeType.GENESIS);
        assertEq(remaining, 53);
        
        console.log("=== Get Remaining Quota Test Passed ===");
        console.log("Genesis remaining quota:", remaining);
    }

    function testGetTotalPurchased() public {
        vm.prank(user2);
        presale.bindReferrer(user1);

        vm.prank(user2);
        usdt.approve(address(presale), 1000 * 10**18);

        vm.prank(user2);
        presale.purchaseNode(INodeRegistry.NodeType.COMMUNITY, PresaleUpgradeable.PaymentToken.USDT);

        assertEq(presale.totalPurchased(), 1000 * 10**18);
        
        console.log("=== Get Total Purchased Test Passed ===");
        console.log("Total purchased:", presale.totalPurchased() / 10**18, "USDT");
    }

    // ============ 权限测试 ============

    function testOnlyOwnerCanUpdateConfig() public {
        vm.prank(user1);
        vm.expectRevert();
        nodeRegistry.updateNodeConfig(
            NodeRegistry.NodeType.COMMUNITY,
            2000 * 10**18,
            100,
            9000,
            0
        );
        
        console.log("=== Only Owner Can Update Config Test Passed ===");
    }

    function testOnlyOwnerCanSetPresaleActive() public {
        vm.prank(user1);
        vm.expectRevert();
        presale.setPresaleActive(false);
        
        console.log("=== Only Owner Can Set Presale Active Test Passed ===");
    }
}
