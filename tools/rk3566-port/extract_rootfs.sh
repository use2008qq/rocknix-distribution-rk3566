#!/bin/bash
# 从 ROCKNIX 构建产物中提取 rootfs（构建完成后运行）
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

DIST=/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution
OUT=/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix-rootfs
cd "$DIST" || exit 1
mkdir -p "$OUT"

echo "===== 1. 定位产物 ====="
RELEASE=$(ls -d target/ROCKNIX-RK3566.aarch64-* 2>/dev/null | grep -v '\.system$\|\.kernel$\|\.tar$' | head -1)
echo "release 目录: ${RELEASE:-<未找到>}"

# 候选路径：release/target/SYSTEM  >  target/*.system  >  build.*/image/system
SYS=""
[ -n "$RELEASE" ] && [ -f "$RELEASE/target/SYSTEM" ] && SYS="$RELEASE/target/SYSTEM"
[ -z "$SYS" ] && SYS=$(ls target/ROCKNIX-RK3566.aarch64-*.system 2>/dev/null | head -1)
TREE="build.ROCKNIX-RK3566.aarch64/image/system"
echo "squashfs: ${SYS:-<未找到>}"
echo "解包树:   ${TREE}"

echo
echo "===== 2. release 目录结构 ====="
[ -n "$RELEASE" ] && find "$RELEASE" -maxdepth 2 | sed "s|$RELEASE|.|" | sort | head -40

echo
echo "===== 3. 拷贝产物 ====="
[ -n "$RELEASE" ] && cp -a "$RELEASE/target" "$OUT/" 2>/dev/null
for d in boot bsp; do
    [ -n "$RELEASE" ] && [ -d "$RELEASE/$d" ] && cp -a "$RELEASE/$d" "$OUT/"
done
# 顶层 squashfs / kernel 也拷一份
for f in "$SYS" "$RELEASE/target/KERNEL"; do
    [ -f "$f" ] && cp -a "$f" "$OUT/" 2>/dev/null
done
ls -la "$OUT" | head -20

echo
echo "===== 4. 解包 squashfs ====="
if [ -f "$SYS" ]; then
    echo "SYSTEM 大小: $(du -h "$SYS" | cut -f1)"
    rm -rf "$OUT/system"
    if command -v unsquashfs >/dev/null 2>&1; then
        if unsquashfs -f -d "$OUT/system" "$SYS" >/dev/null 2>&1; then
            echo "解包完成 -> $OUT/system"
        else
            echo "!! unsquashfs 失败，改用构建目录树"
            cp -a "$TREE" "$OUT/system" 2>/dev/null
        fi
    else
        echo "!! 无 unsquashfs，改用构建目录树"
        cp -a "$TREE" "$OUT/system" 2>/dev/null
    fi
elif [ -d "$TREE" ]; then
    echo "无 squashfs，直接拷贝构建目录树"
    cp -a "$TREE" "$OUT/system"
fi

echo
echo "===== 5. 校验和 ====="
( cd "$OUT" && find . -maxdepth 2 -type f \( -name "SYSTEM" -o -name "KERNEL" -o -name "*.system" \) -exec sha256sum {} \; ) 2>/dev/null

echo
echo "===== 6. rootfs 概览 ====="
if [ -d "$OUT/system" ]; then
    echo "总大小: $(du -sh "$OUT/system" | cut -f1)"
    echo "文件数: $(find "$OUT/system" -type f | wc -l)"
    echo "--- 顶层 ---"; ls "$OUT/system"
    echo "--- 关键组件 ---"
    for c in usr/bin/rocknix usr/bin/emulationstation usr/bin/kodi usr/lib/systemd/systemd usr/lib/autostart/quirks; do
        [ -e "$OUT/system/$c" ] && echo "  有 $c" || echo "  无 $c"
    done
    echo "--- quirks 板级目录数 ---"
    ls "$OUT/system/usr/lib/autostart/quirks/devices" 2>/dev/null | wc -l
    echo "--- 内核模块（你的 Image 内建驱动则用不上）---"
    ls "$OUT/system/lib/modules" 2>/dev/null | head -5 || echo "  (无)"
fi

echo
echo "===== 7. 输出目录 ====="
du -sh "$OUT"; find "$OUT" -maxdepth 1 | sed "s|$OUT|.|"
