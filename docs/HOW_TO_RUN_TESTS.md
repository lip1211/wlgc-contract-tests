# 如何运行测试

## 方法1：使用一键脚本（推荐）

### 步骤1：下载文件

从附件中下载以下文件到本地：
- `run_all_tests.sh` - 完整测试脚本
- `quick_test.sh` - 快速测试脚本
- `PerpetualBond.t.sol` - 永动债券测试
- `WlgcToken.t.sol` - 代币测试
- `Integration.t.sol` - 集成测试
- `Security.t.sol` - 安全测试

### 步骤2：上传到服务器

在您的本地终端（不是AWS浏览器终端）执行：

```bash
# 上传测试文件
scp -i defi.pem PerpetualBond.t.sol ec2-user@3.113.1.77:/home/ec2-user/wlgcfinance/test/
scp -i defi.pem WlgcToken.t.sol ec2-user@3.113.1.77:/home/ec2-user/wlgcfinance/test/
scp -i defi.pem Integration.t.sol ec2-user@3.113.1.77:/home/ec2-user/wlgcfinance/test/
scp -i defi.pem Security.t.sol ec2-user@3.113.1.77:/home/ec2-user/wlgcfinance/test/

# 上传测试脚本
scp -i defi.pem run_all_tests.sh ec2-user@3.113.1.77:/home/ec2-user/
scp -i defi.pem quick_test.sh ec2-user@3.113.1.77:/home/ec2-user/
```

### 步骤3：在AWS浏览器终端运行

在您打开的AWS EC2 Instance Connect终端中输入：

```bash
# 给脚本执行权限
chmod +x /home/ec2-user/run_all_tests.sh
chmod +x /home/ec2-user/quick_test.sh

# 运行完整测试（推荐）
bash /home/ec2-user/run_all_tests.sh

# 或者运行快速测试
bash /home/ec2-user/quick_test.sh
```

### 步骤4：查看结果

测试完成后，您会看到：
- 每个测试的通过/失败状态
- Gas消耗报告
- 覆盖率报告

请截图或复制结果给我进行分析！

---

## 方法2：手动运行（如果脚本有问题）

在AWS终端中依次输入：

```bash
# 进入项目目录
cd /home/ec2-user/wlgcfinance

# 设置PATH
export PATH="$HOME/.foundry/bin:$PATH"

# 运行所有测试
forge test

# 生成详细报告
forge test -vv

# 生成Gas报告
forge test --gas-report

# 生成覆盖率报告
forge coverage
```

---

## 方法3：只运行特定测试

```bash
cd /home/ec2-user/wlgcfinance
export PATH="$HOME/.foundry/bin:$PATH"

# 运行PerpetualBond测试
forge test --match-contract PerpetualBondTest -vv

# 运行WlgcToken测试
forge test --match-contract WlgcTokenTest -vv

# 运行集成测试
forge test --match-contract IntegrationTest -vv

# 运行安全测试
forge test --match-contract SecurityTest -vv
```

---

## 预期结果

如果一切正常，您应该看到：

```
[PASS] testXXX() (gas: XXXXX)
[PASS] testYYY() (gas: XXXXX)
...

Test result: ok. 227 passed; 0 failed; finished in XXms
```

- **总测试数**: 227个
- **预期通过**: 227个
- **预期失败**: 0个
- **预期覆盖率**: 85-90%

---

## 如果遇到问题

### 问题1：找不到forge命令

```bash
# 重新安装foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

### 问题2：编译错误

```bash
# 重新安装依赖
cd /home/ec2-user/wlgcfinance
forge install
```

### 问题3：测试文件找不到

```bash
# 检查测试文件是否存在
ls -la /home/ec2-user/wlgcfinance/test/

# 如果缺少文件，重新上传
```

---

## 需要帮助？

如果遇到任何问题，请：
1. 截图错误信息
2. 复制完整的错误日志
3. 告诉我您执行的命令

我会帮您分析和解决！
