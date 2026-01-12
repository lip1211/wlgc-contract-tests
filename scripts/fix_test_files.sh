#!/bin/bash

# 一键修复测试文件脚本
# 此脚本将从GitHub下载修复后的测试文件并替换服务器上的旧文件

set -e  # 遇到错误立即退出

echo "=========================================="
echo "修复wlgcfinance测试文件"
echo "=========================================="
echo ""

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否在正确的目录
if [ ! -d "/home/ec2-user/wlgcfinance" ]; then
    echo -e "${RED}错误: /home/ec2-user/wlgcfinance 目录不存在${NC}"
    exit 1
fi

echo -e "${YELLOW}步骤1: 备份现有测试文件${NC}"
echo "----------------------------------------"
cd /home/ec2-user/wlgcfinance/test
mkdir -p backup_$(date +%Y%m%d_%H%M%S)
if [ -f "PerpetualBond.t.sol" ]; then
    cp PerpetualBond.t.sol backup_$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
fi
if [ -f "WlgcToken.t.sol" ]; then
    cp WlgcToken.t.sol backup_$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
fi
if [ -f "Integration.t.sol" ]; then
    cp Integration.t.sol backup_$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
fi
if [ -f "Security.t.sol" ]; then
    cp Security.t.sol backup_$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
fi
echo -e "${GREEN}✓ 备份完成${NC}"
echo ""

echo -e "${YELLOW}步骤2: 从GitHub下载修复后的文件${NC}"
echo "----------------------------------------"

# GitHub raw文件URL
BASE_URL="https://raw.githubusercontent.com/lip1211/wlgc-contract-tests/master/test"

# 下载文件
echo "下载 PerpetualBond.t.sol..."
curl -s -o PerpetualBond.t.sol "$BASE_URL/PerpetualBond.t.sol"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PerpetualBond.t.sol 下载成功${NC}"
else
    echo -e "${RED}✗ PerpetualBond.t.sol 下载失败${NC}"
    exit 1
fi

echo "下载 WlgcToken.t.sol..."
curl -s -o WlgcToken.t.sol "$BASE_URL/WlgcToken.t.sol"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ WlgcToken.t.sol 下载成功${NC}"
else
    echo -e "${RED}✗ WlgcToken.t.sol 下载失败${NC}"
    exit 1
fi

echo "下载 Integration.t.sol..."
curl -s -o Integration.t.sol "$BASE_URL/Integration.t.sol"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Integration.t.sol 下载成功${NC}"
else
    echo -e "${RED}✗ Integration.t.sol 下载失败${NC}"
    exit 1
fi

echo "下载 Security.t.sol..."
curl -s -o Security.t.sol "$BASE_URL/Security.t.sol"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Security.t.sol 下载成功${NC}"
else
    echo -e "${RED}✗ Security.t.sol 下载失败${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}步骤3: 验证文件内容${NC}"
echo "----------------------------------------"
# 检查import路径是否正确
if grep -q 'import "../contracts/MockERC20.sol"' PerpetualBond.t.sol; then
    echo -e "${GREEN}✓ PerpetualBond.t.sol import路径正确${NC}"
else
    echo -e "${RED}✗ PerpetualBond.t.sol import路径仍然错误${NC}"
    echo "文件内容:"
    head -10 PerpetualBond.t.sol
    exit 1
fi

echo ""

echo -e "${YELLOW}步骤4: 运行测试验证${NC}"
echo "----------------------------------------"
cd /home/ec2-user/wlgcfinance
export PATH="$HOME/.foundry/bin:$PATH"

echo "编译合约..."
forge build
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 编译成功${NC}"
else
    echo -e "${RED}✗ 编译失败${NC}"
    exit 1
fi

echo ""
echo "运行测试..."
forge test
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过${NC}"
else
    echo -e "${YELLOW}⚠ 部分测试失败，但文件已更新${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}修复完成！${NC}"
echo "=========================================="
echo ""
echo "备份文件位于: /home/ec2-user/wlgcfinance/test/backup_*/"
echo "现在可以运行: cd /home/ec2-user/wlgcfinance && forge test"
echo ""
