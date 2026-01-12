#!/bin/bash

# 一键运行所有测试脚本
# 使用方法: bash run_all_tests.sh

echo "=========================================="
echo "wlgcfinance 项目完整测试套件"
echo "=========================================="
echo ""

# 设置颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 进入项目目录
cd /home/ec2-user/wlgcfinance || exit 1

# 设置PATH
export PATH="$HOME/.foundry/bin:$PATH"

echo -e "${YELLOW}步骤1: 检查环境${NC}"
echo "----------------------------------------"
forge --version
echo ""

echo -e "${YELLOW}步骤2: 运行已验证的测试 (92个)${NC}"
echo "----------------------------------------"
echo "运行 PresaleCompleteTest..."
forge test --match-contract PresaleCompleteTest -vv

echo ""
echo "运行 HashPowerCenterTest..."
forge test --match-contract HashPowerCenterTest -vv

echo ""
echo "运行 StakingManagerTest..."
forge test --match-contract StakingManagerTest -vv

echo ""
echo "运行 WithdrawalManagerTest..."
forge test --match-contract WithdrawalManagerTest -vv

echo ""
echo -e "${YELLOW}步骤3: 运行待验证的测试 (85个)${NC}"
echo "----------------------------------------"
echo "运行 PerpetualBondTest..."
forge test --match-contract PerpetualBondTest -vv

echo ""
echo "运行 WlgcTokenTest..."
forge test --match-contract WlgcTokenTest -vv

echo ""
echo -e "${YELLOW}步骤4: 运行集成测试 (20个)${NC}"
echo "----------------------------------------"
forge test --match-contract IntegrationTest -vv

echo ""
echo -e "${YELLOW}步骤5: 运行安全测试 (30个)${NC}"
echo "----------------------------------------"
forge test --match-contract SecurityTest -vv

echo ""
echo -e "${YELLOW}步骤6: 运行所有测试并生成报告${NC}"
echo "----------------------------------------"
echo "运行所有测试..."
forge test

echo ""
echo "生成Gas报告..."
forge test --gas-report > gas_report.txt
cat gas_report.txt

echo ""
echo "生成覆盖率报告..."
forge coverage > coverage_report.txt
cat coverage_report.txt

echo ""
echo -e "${GREEN}=========================================="
echo "测试完成！"
echo "==========================================${NC}"
echo ""
echo "报告文件已生成:"
echo "  - gas_report.txt (Gas消耗报告)"
echo "  - coverage_report.txt (覆盖率报告)"
echo ""
echo "请将测试结果分享给我进行分析！"
