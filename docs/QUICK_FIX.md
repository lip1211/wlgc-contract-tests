# 快速修复指南

## 问题

服务器上的测试文件还是旧版本（包含错误的import路径），需要更新为GitHub上修复后的版本。

## 解决方案（在服务器上执行）

### 方法1：重新克隆并复制（推荐）

```bash
# 删除旧的测试仓库
cd /home/ec2-user
rm -rf wlgc-contract-tests

# 重新克隆修复后的仓库
git clone https://github.com/lip1211/wlgc-contract-tests.git

# 删除旧的测试文件
rm -f wlgcfinance/test/PerpetualBond.t.sol
rm -f wlgcfinance/test/WlgcToken.t.sol
rm -f wlgcfinance/test/Integration.t.sol
rm -f wlgcfinance/test/Security.t.sol

# 复制修复后的文件
cp wlgc-contract-tests/test/*.sol wlgcfinance/test/

# 运行测试
cd wlgcfinance
export PATH="$HOME/.foundry/bin:$PATH"
forge test
```

### 方法2：直接从GitHub下载（更快）

```bash
cd /home/ec2-user/wlgcfinance/test

# 下载修复后的文件（覆盖旧文件）
wget -O PerpetualBond.t.sol https://raw.githubusercontent.com/lip1211/wlgc-contract-tests/master/test/PerpetualBond.t.sol

wget -O WlgcToken.t.sol https://raw.githubusercontent.com/lip1211/wlgc-contract-tests/master/test/WlgcToken.t.sol

wget -O Integration.t.sol https://raw.githubusercontent.com/lip1211/wlgc-contract-tests/master/test/Integration.t.sol

wget -O Security.t.sol https://raw.githubusercontent.com/lip1211/wlgc-contract-tests/master/test/Security.t.sol

# 运行测试
cd /home/ec2-user/wlgcfinance
export PATH="$HOME/.foundry/bin:$PATH"
forge test
```

### 方法3：手动检查并修复

```bash
# 检查当前文件的import行
cd /home/ec2-user/wlgcfinance/test
head -10 PerpetualBond.t.sol

# 如果看到错误的import路径，需要重新下载
```

## 验证修复

修复后，PerpetualBond.t.sol 的前几行应该是：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PerpetualBondUpgradeable.sol";
import "../contracts/MockERC20.sol";
// MockWlgcToken will be defined inline
```

**注意**：
- ✅ 正确: `import "../contracts/MockERC20.sol";`
- ❌ 错误: `import "../contracts/mocks/MockERC20.sol";`

## 运行测试

```bash
cd /home/ec2-user/wlgcfinance
export PATH="$HOME/.foundry/bin:$PATH"
forge test
```

## 如果还有问题

请执行以下命令并分享输出：

```bash
# 检查文件内容
head -10 /home/ec2-user/wlgcfinance/test/PerpetualBond.t.sol

# 检查文件是否存在
ls -la /home/ec2-user/wlgcfinance/contracts/MockERC20.sol
```

---

**GitHub仓库**: https://github.com/lip1211/wlgc-contract-tests

**最新commit**: 433087b（包含所有修复）
