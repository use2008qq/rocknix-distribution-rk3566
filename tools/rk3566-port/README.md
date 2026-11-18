# rk3566-port tools

RK3566 / GM800 构建过程中写的排障与保障脚本。

**注意：多数脚本内含硬编码路径**（`/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/...`），换机器时需要先改路径。

---

## 一、源码稳定性保障（推荐先用这套）

问题的本质：`sources/` 下 **1600+ 个包是 tarball**（走 SHA256 校验，几乎不出错），
但 **35 个是 git 仓库，共 15.5G，其中 28 个带子模块** —— 全部下载失败都出在这 35 个上。

| 脚本 | 用途 |
|---|---|
| `snapshot-sources.sh` | 把这 35 个 git 包打包成 `sources-git-<日期>.tar.zst`（15.5G → 约 8.3G） |
| `restore-sources.sh` | 一键还原（支持分卷），还原后 pkgbuilder 直接复用，不再联网 |
| `repair-sources.sh` | 扫描/修复 detached HEAD、空工作树、未初始化子模块 |
| `build-with-retry.sh` | 构建 + 失败自动修复 + 重跑（最多 N 次） |

### 典型用法

**新机器首次构建：**

```bash
git clone https://github.com/use2008qq/rocknix-distribution-rk3566.git
cd rocknix-distribution-rk3566

# 下载源码快照（8 卷，共 8.3G，直连约 20 分钟）
gh release download sources-20261118 \
  --repo use2008qq/rocknix-distribution-rk3566 \
  --pattern '*.part-*' --pattern '*.sha256' \
  --dir ./snapshot

# 还原本地源码（自动识别分卷、自动校验 sha256）
tools/rk3566-port/restore-sources.sh . ./snapshot/sources-git-20261118-1157.tar.zst.part-00

# 剩余 1600+ 个 tarball 仍需下载，但几乎不会失败
su builder -c './scripts/build_distro'
```

> 快照地址：https://github.com/use2008qq/rocknix-distribution-rk3566/releases/tag/sources-20261118
> 下载时**不要走代理**：实测直连 7.2 MB/s，走代理仅 575 KB/s。

**构建卡住 / 反复 clone 同一个包：**

```bash
# 先 Ctrl-C 停掉，再修复
tools/rk3566-port/repair-sources.sh . --fix
su builder -c './scripts/build_distro'
```

**全自动：**

```bash
tools/rk3566-port/build-with-retry.sh 3 /path/to/sources-git-20261118-1157.tar.zst
```

### 快照分卷（GitHub Release 单文件限制 2G）

```bash
# 拆分
split -b 1800M sources-git-20261118-1157.tar.zst sources-git-20261118-1157.tar.zst.part-

# 还原时脚本会自动识别并合并
restore-sources.sh . sources-git-20261118-1157.tar.zst.part-aa
```

---

## 二、构建与监控

| 脚本 | 用途 |
|---|---|
| `run_rocknix_build.sh` | 启动构建并落日志 |
| `resume_aarch64.sh` | 中断后断点续跑 |
| `build_watch.sh` | 盯构建进度（简版） |
| `watch2.sh` | 盯构建进度（带包级过滤） |
| `check_missing_sources.py` | 扫描 `sources/` 下缺失或为空的包 |
| `fix_file_source.sh` | 修复 `file://` 类型源码未落盘 |

## 三、设备树 / 镜像

| 脚本 | 用途 |
|---|---|
| `build_dts.sh` | 编译并提取设备树 |
| `fix_dts.py` | 修正 dts 中的节点/引用错误 |
| `dts_extract.py` | 从镜像或 dtb 中提取 dts |
| `dts_resolve.py` | 解析 dts 包含关系，定位符号来源 |
| `dts_delta.py` | 比对两份 dts 的差异 |
| `gen_panel_patch.py` | 根据面板参数生成 kernel patch |
| `extract_rootfs.sh` | 从 `.img` 中提取 rootfs 用于检查 |

---

## 四、常用排查片段

**某个包卡在反复 clone？**

```bash
tail -f build.ROCKNIX-RK3566.aarch64/.threads/logs/<seq>.log
```

**子模块是否真的下全了？**

```bash
cd sources/<pkg>/<pkg>-<version>
git submodule status --recursive | grep '^-'    # '-' 开头 = 未初始化
```

**单包重来：**

```bash
B=build.ROCKNIX-RK3566.aarch64
rm -rf $B/build/<pkg>-<version>       # 强制重新 unpack
rm -rf sources/<pkg>/<pkg>-<version>  # 连源码一起重下
```
