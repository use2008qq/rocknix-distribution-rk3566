# 新机器从零编译 RK3566 固件

本仓库（fork）已经把源码适配固化，clone 下来就是改好的树。但 **`sources/`、`build.*/`、`target/` 都在 `.gitignore` 里**——git 只管代码，不管下载的第三方源码。

所以流程是：**clone → 还原源码 → 编译**。快照不会自动解压，必须手动跑一次还原脚本。

---

## 0. 前提

| 项目 | 要求 |
|---|---|
| 系统 | Linux x86_64（Ubuntu 22.04 / 24.04 实测可用）。**Windows 原生不行**，WSL2 也不建议——`kpartx`/loop device 受限，出镜像会失败 |
| 磁盘 | ≥ 100G 可用（源码 24G + 编译中间产物 + 镜像） |
| 内存 | ≥ 8G（`ld` 阶段链接大型程序会吃满） |
| 用户 | **不能用 root 构建**，`config/options` 会直接拒绝 |
| 网络 | 需要能访问 GitHub（拉 tarball 包） |

---

## 1. 安装依赖

```bash
sudo apt update
sudo apt install -y git curl wget zstd build-essential bc bison flex \
  libssl-dev libncurses5-dev rsync unzip cpio python3 python3-pip \
  device-tree-compiler uuid-runtime kpartx
```

漏装也不致命：`scripts/build_distro` 第一步就调 `scripts/checkdeps`，缺什么会列出来并询问是否自动安装。

---

## 2. 克隆仓库

```bash
git clone https://github.com/use2008qq/rocknix-distribution-rk3566.git
cd rocknix-distribution-rk3566
```

默认分支已经是 `rk3566-gm800`，**不用 checkout**。适配（SDL2 / freej2me-lr / azahar-sa / GM800 quirk）都在里面。

---

## 3. 获取源码快照

`distribution` 自身没有 submodule，597 个包的源码是构建时从各自上游现下的。其中 **35 个是 git 仓库（15.5G，28 个带子模块）**，历史上所有下载失败都出在这 35 个上；剩下 1600+ 个是 tarball，走 SHA256 校验，基本不出错。

快照就是把这 35 个 git 包打包成 8.3G，还原后它们一个字节都不再联网。

### 方式 A：从构建机内网拷贝（实测可用，推荐）

```bash
scp -r root@192.168.6.79:/root/sources-snapshot ./
```

`/root/sources-snapshot/` 内容：

```
sources-git-20261118-1157.tar.zst              8.3G   整包
sources-git-20261118-1157.tar.zst.part-00..07  8×1.1G 分卷（与整包等价，二选一）
sources-git-20261118-1157.tar.zst.sha256
sources-git-20261118-1157.manifest.txt
```

只拷分卷也行，脚本会自动合并。

### 方式 B：GitHub Release

```bash
gh release download sources-20261118 \
  --repo use2008qq/rocknix-distribution-rk3566 \
  --pattern '*.part-*' --pattern '*.sha256' \
  --dir ./sources-snapshot
```

> ⚠️ 8 卷已全部上传成功，但 **GitHub Release 的大文件下载在国内网络基本不通**（上传走 `uploads.github.com` 通畅，下载走 `objects.githubusercontent.com` 被墙；实测直连超时、代理 000、三个加速站全超时）。当冷备份留着，别指望它。

---

## 4. 还原源码

```bash
tools/rk3566-port/restore-sources.sh . ./sources-snapshot
```

传目录即可，脚本会自动找到整包或分卷。它会依次：

1. 分卷合并（若传入的是 `*.part-00`）
2. **sha256 校验**（合并后按哈希值比对，不依赖文件名）
3. 解包到 `./sources/`
4. **修正属主**——以 root 运行时自动改回仓库属主，否则普通用户构建时无权写入
5. 健康检查：有效 HEAD / 是否 detached HEAD

正常输出：

```
检测到分卷，共 8 个
  合并中（约 8G）...
校验快照完整性...
  sha256 OK
还原到 /path/sources ...
修正属主为 builder ...
还原完成，检查仓库状态：
  共检查 35 个 git 仓库
  状态全部正常
```

看到 `状态全部正常` 就可以往下走。如果提示 detached HEAD，跑 `tools/rk3566-port/repair-sources.sh . --fix`。

> 没有快照也能编，只是这 35 个包要现场下载，容易在 ppsspp-lr / dolphin-sa / vita3k-sa 上翻车。

---

## 5. 编译

**标准流程（上游 Makefile 方式，先 arm 后 aarch64 两趟）：**

```bash
make RK3566
```

耗时参考（16 核）：arm 趟 253 个包约 2 小时，aarch64 趟 695 个包约 6～8 小时。

**只跑 aarch64 趟（省一半时间，出镜像的就是这一趟）：**

```bash
ARCH=aarch64 PROJECT=ROCKNIX DEVICE=RK3566 DEVICE_ROOT=RK3566 ./scripts/build_distro
```

**必须以普通用户运行。** 如果是 root 登录的机器，先建普通用户并把仓库给它：

```bash
useradd -m -s /bin/bash builder
chown -R builder:builder /path/to/rocknix-distribution-rk3566
su builder -c 'cd /path/to/rocknix-distribution-rk3566 && make RK3566'
```

**如果下载慢，挂代理**（只影响 tarball 下载，不影响快照还原）：

```bash
export http_proxy=http://192.168.6.121:7890
export https_proxy=$http_proxy HTTP_PROXY=$http_proxy HTTPS_PROXY=$http_proxy
```

`make RK3566` 建议放后台跑，SSH 断线不会中断：

```bash
setsid nohup make RK3566 > build.log 2>&1 < /dev/null &
tail -f build.log
```

---

## 6. 产物位置

```
distribution/target/
  ROCKNIX-RK3566.aarch64-<日期>-Generic.img.gz    约 1.4G，启动时自动匹配设备
  ROCKNIX-RK3566.aarch64-<日期>-Specific.img.gz   约 1.4G，固定 rk3566-powkiddy-x55.dtb
  ROCKNIX-RK3566.aarch64-<日期>.tar
  对应的 .sha256
```

校验：

```bash
cd target && sha256sum -c *.sha256
gzip -t ROCKNIX-RK3566.aarch64-*.img.gz && echo OK
```

烧写：解压 `.img.gz` 后写 TF 卡（`dd` 或 balenaEtcher / Rufus）。

---

## 7. 中断了怎么续跑

pkgbuilder 用 `build.ROCKNIX-RK3566.aarch64/.threads/joblog` 记录已完成任务，**重跑同一条命令就是断点续跑**，不会从头再来。

查看进度：

```bash
B=build.ROCKNIX-RK3566.aarch64
grep -c '^DONE' $B/.threads/joblog     # 已完成
grep -cE '^(FAIL|ERROR)' $B/.threads/joblog   # 失败
```

单个包卡住反复 clone → 见 `tools/rk3566-port/README.md` 的 `repair-sources.sh`。

全自动（失败自动修 + 重跑，最多 3 轮）：

```bash
tools/rk3566-port/build-with-retry.sh 3
```

---

## 一句话版

```bash
git clone https://github.com/use2008qq/rocknix-distribution-rk3566.git
cd rocknix-distribution-rk3566
scp -r root@192.168.6.79:/root/sources-snapshot ./          # 或自行下载 Release
tools/rk3566-port/restore-sources.sh . ./sources-snapshot   # 这步不能省
make RK3566
# 产物在 target/
```
