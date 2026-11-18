# RK3566 / GM800 适配说明

本分支（`rk3566-gm800`）基于上游 `ROCKNIX/distribution` 的 `next`，包含在 **RK3566 / GM800 谷美云智能音箱** 上完成一次完整构建（695 包，0 失败）所需的全部源码级适配。

验证产物：`ROCKNIX-RK3566.aarch64-20261118`（Generic + Specific 两个镜像）

---

## 一、本分支的改动

| 文件 | 改动 | 原因 |
|---|---|---|
| `projects/ROCKNIX/packages/graphics/SDL2/package.mk` | host 构建关闭全部 video/audio 后端 | 构建机有 `libXext.so.6` 但缺 `Xext.h`，cmake 探测 X11 失败。host SDL2 只是 `gzdoom-sa:host` 的构建工具，运行时不需要后端 |
| `projects/ROCKNIX/packages/emulators/libretro/freej2me-lr/package.mk` | `build.xml` 的 `value="1.6"` → `1.8` | freej2me 1.52 硬编码 Java 6 级别，JDK 21 已移除 |
| `projects/ROCKNIX/packages/emulators/standalone/azahar-sa/package.mk` | `-DENABLE_FFMPEG=OFF` | 系统 FFmpeg 9（avutil 61）与 azahar 要求的 FFmpeg 7（avutil 59）ABI 不兼容。代价：失去录像功能 |
| `documentation/PER_DEVICE_DOCUMENTATION/RK3566/SUPPORTED_EMULATORS_AND_CORES.md` | gb/gba/gbc 增加 `armgba` core | 文档与实际编进镜像的 core 对齐 |
| `.../hardware/quirks/devices/GM800 Guomeiyun Smart Speaker/` | 新增设备 quirk（5 文件） | 设备探测、音频通路、触摸、设备配置 |

> `GM800 Guomeiyun Smart Speaker` 目录名含空格，是上游 quirks 的既有命名约定，不要改名。

同步上游更新：

```bash
git fetch origin next
git merge origin/next      # 冲突通常只在上面 4 个文件
```

---

## 二、构建

```bash
# 必须用普通用户，root 会被 build_distro 拒绝
su builder -c './scripts/build_distro'

# 并行度（4 核机器）
scripts/pkgbuilder.py --max-procs 4 --halt-on-error
THREADCOUNT=4

# 网络代理
export http_proxy=http://<proxy>:7890
export https_proxy=http://<proxy>:7890
```

磁盘峰值约 100G（sources + build + target）。`sources/` 最终约 24G，597 个包。

### 判断构建是否真的结束

**不要**看 `make image` 进程在不在——`build_distro` 会在 pkgbuilder 收尾阶段就并行启动 `make image`，此时还有包在编译。

```bash
B=build.ROCKNIX-RK3566.aarch64
grep -c '^DONE' $B/.threads/joblog          # 必须等于 plan.json 条数（695）
grep -cE '^(FAIL|ERROR)' $B/.threads/joblog  # 必须为 0
```

### 镜像位置

镜像**不在** `$B/image/`（那里只是临时 rootfs 组装区，约 4.4G），而在：

```
target/ROCKNIX-RK3566.aarch64-<日期>-Generic.img.gz
target/ROCKNIX-RK3566.aarch64-<日期>-Specific.img.gz
target/ROCKNIX-RK3566.aarch64-<日期>.tar
```

- **Generic**：启动时自动匹配设备树
- **Specific**：`extlinux.conf` 的 FDT 写死为指定设备（本次 `rk3566-powkiddy-x55.dtb`）

---

## 三、源码下载 / 子模块类失败（最高频）

> **注意**：本仓库**没有** `.gitmodules`。597 个包的源码都是 `package.mk` 在构建时从各自上游现场 clone/下载的，因此 **fork 本仓库并不能把源码一起带走**。包自身的 git 子模块（如 ppsspp 的 ffmpeg、armips）仍需联网拉取。

### 通用机制：get_git 的判定链

`pkgbuilder` 下载源码后，用 `_repo_exists_and_valid` 判断已有仓库能否复用：

1. `_clean_repo`：`git clean -fdx` + `git restore --staged . || git switch --force`
2. `git ls-remote . | grep -q -m1 "^${PKG_VERSION}"`
3. origin URL 匹配

**任一环节失败 → 整个源码目录被删除重新下载**，表现为同一包反复 checkout、耗时数小时。

两个致命细节：

- **HEAD 处于 detached 状态** 时 `git switch --force` 失败 → 判定无效 → **删库重下死循环**
- `PKG_VERSION` 常是 **tag 解引用后的 commit**（如 ppsspp 的 `fa50bb1` = `refs/tags/v1.20.4^{}`），`--no-tags` 克隆拿不到该对象

### 解法模板

```bash
cd sources/<pkg>/<pkg>-<PKG_VERSION>
git clone --branch <tag> --depth 1 <url> tmp && mv tmp/* .
git checkout -b rocknix-pin          # 必须落本地分支，不能 detached
git submodule update --init --recursive --depth 1
```

### 逐包记录

| 包 | 症状 | 原因 / 解法 |
|---|---|---|
| `ppsspp-lr` | 无限重新 clone，循环数小时 | `PKG_VERSION=fa50bb1` 是 `v1.20.4` 的 tag 解引用 commit。改 `git clone --branch v1.20.4 --depth 1` + `git checkout -b rocknix-pin` |
| `ppsspp-lr` (ffmpeg) | 子模块 clone 反复超时 | ffmpeg 子模块 300M+。实际只需 `ffmpeg/linux_arm64.sh`（patch 006 引用，`USE_SYSTEM_FFMPEG=ON`），可用 raw 单文件占位 |
| `ppsspp-lr` (armips) | CMake `add_subdirectory(ext/filesystem)` 失败 | `armips/ext/filesystem` 为空。递归补子模块后**必须删除 build 目录**强制重新 unpack，否则仍在旧空目录上编译 |
| `dolphin-sa` | patch 打不上 | 工作区 HEAD ≠ `PKG_VERSION`（`6094cfcf`）。`git checkout -B rocknix-pin 6094cfcf` 对齐后通过 |
| `azahar-sa` | 编译期 avutil 版本冲突 | 见上方 `ENABLE_FFMPEG=OFF` 适配 |
| `azahar-sa` | 嵌套子模块 `cubeb/cmake/sanitizers-cmake` 缺失 | 按**一级子模块**逐个 `git submodule update --init --recursive` |
| `tic80-lr` / `vita3k-sa` | 同类子模块缺失 | 同上递归补齐；`vita3k-sa` 跳过 `Externals/Qt`（Windows 预编译，Linux 用系统 qt6） |
| `armsx2-sa` | 末尾 wget 下载 `pcsx2_patches` SSL 中断 | 手工 `curl -L` 下载 `archive/refs/tags/latest.zip` 到 `bin/resources/patches.zip`，`unzip -t` 校验后重跑即过 |

### 陷阱：子模块"假成功"

`git submodule update --init` 可能只登记 gitlink 而**工作树为空**：

```bash
git submodule status --recursive | grep '^-'    # 前面 '-' 表示未初始化
find <submodule>/ -maxdepth 1 -type f | head    # 空目录 = 假成功
```

补齐后**必须删除对应 build 目录**让 pkgbuilder 重新 unpack。

---

## 四、耗时参考（4 并行）

| 包 | 耗时 |
|---|---|
| `azahar-sa` | 5490 s（约 1.5 h） |
| `dolphin-sa` | 5183 s（约 1.4 h） |
| `vita3k-sa` | 3500 s（约 1 h） |

这几项在跑且 CPU 满载属正常，不要误判卡死。

---

## 五、调试技巧

- 构建日志：`/home/builder/rk3566-rebuild-<日期>.log`（仓库外）
- 单包日志：`$B/.threads/logs/<seq>.log`
- 剩余任务：`plan.json` 是 `[{task,name,section,wants,unpacks}]` 列表，**无 index 字段**，需按 `(name, task)` 与 joblog 第 5、4 列做多重集匹配
- 长命令用 `setsid nohup` 后台 + 日志轮询，避免 SSH 断连中断
- **不要用 `pkill -f`** 清理构建进程，极易误杀自己的 SSH 会话；用精确 PID

---

## 六、源码层稳定性保障（避免重复下载）

### 问题边界

本次构建后统计 `sources/`（24G）：

| 类型 | 数量 | 稳定性 |
|---|---|---|
| tarball / zip | 1636 | 走 `PKG_SHA256` 校验，失败率极低 |
| **git 仓库** | **35（15.5G）** | **全部下载失败都出在这里，其中 28 个带子模块** |

体积集中在少数大包：`ppsspp-sa` 3.1G、`dolphin-sa` 2.1G、`dolphin-lr` 1.7G、`vita3k-sa` 1.5G、`flycast-sa`/`flycast-lr` 各 1.0G、`azahar-sa` 898M。

**结论：只要把这 15.5G 保住，第二层的不稳定基本解决。**

### 快照方案

已发布的快照（8 卷 × 1.1G，共 8.3G）：
https://github.com/use2008qq/rocknix-distribution-rk3566/releases/tag/sources-20261118

```bash
# 新机器：下载并还原（脚本自动识别分卷并校验 sha256）
gh release download sources-20261118 \
  --repo use2008qq/rocknix-distribution-rk3566 \
  --pattern '*.part-*' --pattern '*.sha256' --dir ./snapshot
tools/rk3566-port/restore-sources.sh . ./snapshot/sources-git-20261118-1157.tar.zst.part-00

# 自己重新打包（15.5G -> 8.3G，zstd -T0 -12，约 3 分钟）
tools/rk3566-port/snapshot-sources.sh . /root/sources-snapshot
split -n 8 -d <包>.tar.zst <包>.tar.zst.part-
```

> 下载/上传都**不要走代理**：实测直连 7.2 MB/s，走代理仅 575 KB/s（慢 12 倍）。

还原后 pkgbuilder 判定仓库有效会直接复用，这 35 个包不再联网。

> 快照只含 git 类包，不含 1636 个 tarball —— 后者下载失败率低，且压缩后体积占比小，不值得一并打包。

### 状态巡检

`repair-sources.sh` 会扫描全部 35 个 git 包，检查三类致命状态：

| 状态 | 后果 | 修复 |
|---|---|---|
| HEAD detached | `git switch --force` 失败 → 判定无效 → **删库重下死循环** | `git checkout -B rocknix-pin` |
| 工作树为空 | CMake `add_subdirectory` 失败 | 需重新下载 |
| 子模块仅登记 gitlink | 编译时找不到源文件 | `git submodule update --init --recursive` |

```bash
tools/rk3566-port/repair-sources.sh .          # 只检查
tools/rk3566-port/repair-sources.sh . --fix    # 检查并修复
```

**本次检查实际发现 `dolphin-lr` 和 `vita3k-sa` 处于 detached HEAD**，已修复。这两个包若下次构建被判定无效，会白等 20～30 分钟重新下载。

已知故意跳过的子模块（脚本不会尝试拉取）：

- `ppsspp-lr` 的 `ffmpeg` — 用占位 `ffmpeg/linux_arm64.sh` 替代（`USE_SYSTEM_FFMPEG=ON`）
- `dolphin-sa` / `vita3k-sa` 的 `Externals/Qt` — Windows 预编译，Linux 用系统 qt6

### 自动重试

```bash
tools/rk3566-port/build-with-retry.sh 3 /path/to/sources-git-<日期>.tar.zst
```

失败后依次：打印失败任务 → 检查 git 包数量是否减少（减少说明触发了删库重下，自动还原快照）→ 修复源码状态 → 重跑。pkgbuilder 靠 `joblog` 跳过已完成包，不会从头再来。
