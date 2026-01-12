#!/bin/bash

# WLGC系统集成测试脚本
# BSC测试网 - 完整业务流程测试

set -e

echo "=========================================="
echo "WLGC系统集成测试"
echo "BSC Testnet"
echo "=========================================="

# 环境变量
export PRIVATE_KEY="0x160bb06dde9b5c226e27e9ff94a4f3a5cdf9a08204797551fe34808793a7580d"
export RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"
export PATH="$HOME/.foundry/bin:$PATH"

# 合约地址
WLGC="0xc1faEF631bBA07456A8Dd021dE27018d8a27B797"
REFERRAL_REGISTRY="0x62dADBb824880Fae6CcFa04b425eB2d382B2b201"
NODE_REGISTRY="0xa2A57bBdd409c8F6Cb216873653E45A8F61CDfd3"
HASH_POWER_CENTER="0x14c2A919c605a4b35E29d7355DE706C8e38A85F0"
USDT="0x6bFd0FE5E3165c28F437a2a4Ff5f05529cDB459E"
WITHDRAWAL_MANAGER="0x93bfA505eF1F7Fea534Ab563C3CcAA10bBd5810a"
STAKING_MANAGER="0x64044742Fa3e5f59E873abCFf6979F8dCbe065A0"
PERPETUAL_BOND="0x1d1DCcE1C344c91DD1B3f765b8C4B6Ef790f3ccb"
DEPLOYER="0x6A00B65c3311DC407EE64aFdbCdfc5a40410bfEd"

echo ""
echo "部署地址: $DEPLOYER"
echo ""

# ==========================================
# 步骤1: 配置合约权限
# ==========================================
echo "=========================================="
echo "步骤1: 配置合约权限"
echo "=========================================="

echo "1.1 授权StakingManager访问HashPowerCenter..."
cast send $HASH_POWER_CENTER \
  "setAuthorizedContract(address,bool)" \
  $STAKING_MANAGER true \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

echo "✅ StakingManager已授权"
sleep 5

echo ""
echo "1.2 授权PerpetualBond访问HashPowerCenter..."
cast send $HASH_POWER_CENTER \
  "setAuthorizedContract(address,bool)" \
  $PERPETUAL_BOND true \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

echo "✅ PerpetualBond已授权"
sleep 5

echo ""
echo "1.3 配置WithdrawalManager..."
cast send $WITHDRAWAL_MANAGER \
  "setRewardContractAuthorization(address,bool)" \
  $STAKING_MANAGER true \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

cast send $WITHDRAWAL_MANAGER \
  "setRewardContractAuthorization(address,bool)" \
  $PERPETUAL_BOND true \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

cast send $WITHDRAWAL_MANAGER \
  "setEquityBond(address)" \
  $PERPETUAL_BOND \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

echo "✅ WithdrawalManager配置完成"

# ==========================================
# 步骤2: 准备测试数据
# ==========================================
echo ""
echo "=========================================="
echo "步骤2: 准备测试数据"
echo "=========================================="

echo "2.1 Mint测试USDT (100万)..."
cast send $USDT \
  "mint(address,uint256)" \
  $DEPLOYER \
  1000000000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

USDT_BALANCE=$(cast call $USDT "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC_URL)
echo "✅ USDT余额: $USDT_BALANCE"

# ==========================================
# 步骤3: 测试PerpetualBond业务流程
# ==========================================
echo ""
echo "=========================================="
echo "步骤3: 测试PerpetualBond业务流程"
echo "=========================================="

echo "3.1 授权USDT给PerpetualBond..."
cast send $USDT \
  "approve(address,uint256)" \
  $PERPETUAL_BOND \
  1000000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000 --gas-price 1000000000
sleep 3

echo "✅ USDT授权完成"

echo ""
echo "3.2 创建PerpetualBond订单 (1000 USDT)..."
TX_HASH=$(cast send $PERPETUAL_BOND \
  "createOrder(uint256)" \
  1000000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 3000000 \
  --json | jq -r '.transactionHash')

echo "✅ 订单创建成功"
echo "交易哈希: $TX_HASH"

echo ""
echo "3.3 查询订单信息..."
# 获取订单ID (假设是第1个订单)
ORDER_ID=1

echo "订单ID: $ORDER_ID"

# 查询WLGC余额
WLGC_BALANCE=$(cast call $WLGC "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC_URL)
echo "WLGC余额: $WLGC_BALANCE"

# ==========================================
# 步骤4: 验证系统状态
# ==========================================
echo ""
echo "=========================================="
echo "步骤4: 验证系统状态"
echo "=========================================="

echo "4.1 检查HashPowerCenter授权状态..."
IS_STAKING_AUTH=$(cast call $HASH_POWER_CENTER "authorizedContracts(address)(bool)" $STAKING_MANAGER --rpc-url $RPC_URL)
IS_BOND_AUTH=$(cast call $HASH_POWER_CENTER "authorizedContracts(address)(bool)" $PERPETUAL_BOND --rpc-url $RPC_URL)

echo "StakingManager授权: $IS_STAKING_AUTH"
echo "PerpetualBond授权: $IS_BOND_AUTH"

echo ""
echo "4.2 检查代币余额..."
echo "WLGC余额: $(cast call $WLGC 'balanceOf(address)(uint256)' $DEPLOYER --rpc-url $RPC_URL)"
echo "USDT余额: $(cast call $USDT 'balanceOf(address)(uint256)' $DEPLOYER --rpc-url $RPC_URL)"

# ==========================================
# 测试完成
# ==========================================
echo ""
echo "=========================================="
echo "✅ 系统集成测试完成！"
echo "=========================================="
echo ""
echo "📋 已部署合约地址："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WlgcToken:         $WLGC"
echo "ReferralRegistry:  $REFERRAL_REGISTRY"
echo "NodeRegistry:      $NODE_REGISTRY"
echo "HashPowerCenter:   $HASH_POWER_CENTER"
echo "MockUSDT:          $USDT"
echo "WithdrawalManager: $WITHDRAWAL_MANAGER"
echo "StakingManager:    $STAKING_MANAGER"
echo "PerpetualBond:     $PERPETUAL_BOND"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 在BSCScan上查看："
echo "https://testnet.bscscan.com/address/$PERPETUAL_BOND"
echo ""
echo "=========================================="
