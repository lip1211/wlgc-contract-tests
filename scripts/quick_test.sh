#!/bin/bash

# 快速测试脚本 - 只运行所有测试一次
# 使用方法: bash quick_test.sh

echo "=========================================="
echo "wlgcfinance 快速测试"
echo "=========================================="
echo ""

# 进入项目目录
cd /home/ec2-user/wlgcfinance || exit 1

# 设置PATH
export PATH="$HOME/.foundry/bin:$PATH"

echo "运行所有测试..."
forge test

echo ""
echo "生成Gas报告..."
forge test --gas-report

echo ""
echo "生成覆盖率报告..."
forge coverage

echo ""
echo "=========================================="
echo "测试完成！"
echo "=========================================="
