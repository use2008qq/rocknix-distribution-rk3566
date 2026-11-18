# rk3566-port tools

RK3566 / GM800 构建过程中写的排障脚本。

**注意：多数脚本内含硬编码路径**（`/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/...`），换机器或换目录时需要先改路径。这些脚本不是构建流程的一部分，是出问题时的手工工具。

| 脚本 | 用途 |
|---|---|
| `run_rocknix_build.sh` | 启动构建并落日志 |
| `resume_aarch64.sh` | 中断后断点续跑 |
| `build_watch.sh` | 盯构建进度（简版） |
| `watch2.sh` | 盯构建进度（带包级过滤） |
| `check_missing_sources.py` | 扫描 `sources/` 下缺失或为空的包 |
| `fix_file_source.sh` | 修复 `file://` 类型源码未落盘 |
| `build_dts.sh` | 编译并提取设备树 |
| `fix_dts.py` | 修正 dts 中的节点/引用错误 |
| `dts_extract.py` | 从镜像或 dtb 中提取 dts |
| `dts_resolve.py` | 解析 dts 包含关系，定位符号来源 |
| `dts_delta.py` | 比对两份 dts 的差异 |
| `gen_panel_patch.py` | 根据面板参数生成 kernel patch |
| `extract_rootfs.sh` | 从 `.img` 中提取 rootfs 用于检查 |

---

## 常用排查片段

**某个包卡在反复 clone？**

```bash
tail -f build.ROCKNIX-RK3566.aarch64/.threads/logs/<seq>.log
```

配合 `docs`（见 `documentation/PER_DEVICE_DOCUMENTATION/RK3566/GM800-PORT-NOTES.md`）里的 get_git 判定链分析。

**子模块是否真的下全了？**

```bash
cd sources/<pkg>/<pkg>-<version>
git submodule status --recursive | grep '^-'
```

**清理单个包重来：**

```bash
B=build.ROCKNIX-RK3566.aarch64
rm -rf $B/build/<pkg>-<version>      # 强制重新 unpack
rm -rf sources/<pkg>/<pkg>-<version> # 连源码一起重下
```
